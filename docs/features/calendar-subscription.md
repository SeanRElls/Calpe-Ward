# Calendar Subscription Feature

**Status:** Ready for deployment  
**Last Updated:** 2026-01-20

## Overview

The calendar subscription feature allows staff to add their published shift schedule to Apple Calendar, Google Calendar, Outlook, or any calendar app that supports ICS/iCal subscriptions.

## How It Works

### For Users

1. **Generate Token**: Click "Generate Calendar Link" in account settings
2. **Copy URL**: Copy the subscription URL (starts with `https://` or `webcal://`)
3. **Subscribe**: Add to calendar app:
   - **Apple Calendar**: File → New Calendar Subscription
   - **Google Calendar**: Settings → Add calendar → From URL
   - **Outlook**: Add calendar → Subscribe from web
4. **Auto-Sync**: Calendar automatically updates when shifts are published

### Security Model

- **Dedicated tokens**: Separate from login session (rotatable without re-login)
- **Hashed storage**: Tokens are SHA-256 hashed before database storage
- **User-scoped**: Each token only returns that user's shifts
- **Revocable**: Generate new token to invalidate old URLs
- **Published only**: Feed only includes shifts with `status = 'published'`

## Technical Architecture

### Database Schema

```sql
-- Calendar tokens table
calendar_tokens (
  id uuid PRIMARY KEY,
  user_id uuid FK → users(id),
  token_hash text UNIQUE,       -- SHA-256 hash
  created_at timestamptz,
  revoked_at timestamptz,        -- NULL = active
  last_used_at timestamptz
)
```

### RPCs

1. **generate_calendar_token(p_token text)**
   - Requires valid session token
   - Revokes existing token
   - Generates 32-byte random token
   - Returns raw token (only time visible)

2. **revoke_calendar_token(p_token text)**
   - Requires valid session token
   - Revokes all active tokens for user

3. **get_published_shifts_for_calendar(p_calendar_token text)**
   - Validates calendar token (not session token)
   - Returns published shifts for token owner
   - Updates last_used_at timestamp
   - Includes past 30 days + all future shifts

### Edge Function: `/ics`

**Endpoint:** `https://<project>.supabase.co/functions/v1/ics?token=<calendar_token>`

**Flow:**
1. Parse token from query string
2. Hash token (SHA-256)
3. Call `get_published_shifts_for_calendar` RPC
4. Build RFC 5545 compliant ICS
5. Return `text/calendar` with CRLF line endings

**Event Format:**
```
SUMMARY: N - Night Shift
DESCRIPTION: Hours: 20:00 – 08:00
LOCATION: Calpe Ward
UID: shift-<assignment_id>@calpeward
```

### ICS Compliance

- ✅ CRLF line endings (`\r\n`)
- ✅ Proper escaping (backslash, comma, semicolon, newline)
- ✅ Stable UIDs (no duplicates on update)
- ✅ Line folding (max 75 octets)
- ✅ UTC timestamps (`YYYYMMDDTHHMMSSZ`)
- ✅ Overnight shift handling (end date +1 day)

## Data Returned

### Scope
- **User-specific**: Only the token owner's shifts
- **Published only**: `rota_assignments.status = 'published'`
- **Time range**: Past 30 days + all future

### Shift Details
- **Code + Label**: From `shifts` table (catalogue source of truth)
- **Date + Time**: From `rota_assignments.date` + `shifts.start_time/end_time`
- **Hours**: Displayed in DESCRIPTION
- **Location**: "Calpe Ward" (constant)

## Deployment

### 1. Run Migration

```bash
# Deploy SQL migration
psql -h <host> -U <user> -d <database> -f sql/migrations/2026-01-20-calendar-tokens.sql
```

Or via Supabase CLI:
```bash
supabase db push
```

### 2. Deploy Edge Function

```bash
# Deploy to Supabase
supabase functions deploy ics

# Verify deployment
curl -i "https://<project>.supabase.co/functions/v1/ics?token=test"
# Should return 401 Invalid token
```

### 3. Test Flow

```bash
# 1. Generate token via RPC (requires valid session token)
curl -X POST "https://<project>.supabase.co/rest/v1/rpc/generate_calendar_token" \
  -H "apikey: <anon_key>" \
  -H "Authorization: Bearer <session_jwt>" \
  -H "Content-Type: application/json" \
  -d '{"p_token": "<session_token>"}'

# Response: {"success": true, "token": "<64_char_hex>", ...}

# 2. Test calendar feed
curl -i "https://<project>.supabase.co/functions/v1/ics?token=<64_char_hex>"

# Should return:
# HTTP/1.1 200 OK
# Content-Type: text/calendar; charset=utf-8
# 
# BEGIN:VCALENDAR
# VERSION:2.0
# ...
```

## Frontend Integration

### Account Modal UI

Add to `js/user-modal.js`:

```javascript
// Calendar section
const calendarSection = `
  <div class="modal-section">
    <h3>📅 Calendar Subscription</h3>
    <p class="help-text">
      Subscribe to your published shifts in Apple/Google/Outlook Calendar.
    </p>
    
    <div id="calendarTokenStatus"></div>
    
    <div class="button-group">
      <button id="generateCalendarToken" class="btn-primary">
        Generate Calendar Link
      </button>
      <button id="revokeCalendarToken" class="btn-secondary" disabled>
        Revoke Link
      </button>
    </div>
    
    <div id="calendarLinkDisplay" style="display: none;">
      <label>Subscription URL:</label>
      <input type="text" id="calendarURL" readonly />
      <button id="copyCalendarURL" class="btn-icon">📋 Copy</button>
      
      <p class="help-text">
        <strong>webcal://</strong> variant for Apple Calendar:
      </p>
      <input type="text" id="webcalURL" readonly />
    </div>
  </div>
`;
```

### Token Generation

```javascript
async function generateCalendarToken() {
  const { data, error } = await supabaseClient.rpc(
    'generate_calendar_token',
    { p_token: sessionToken }
  );
  
  if (error) {
    alert('Failed to generate token');
    return;
  }
  
  const icsURL = `${SUPABASE_URL}/functions/v1/ics?token=${data.token}`;
  const webcalURL = icsURL.replace('https://', 'webcal://');
  
  document.getElementById('calendarURL').value = icsURL;
  document.getElementById('webcalURL').value = webcalURL;
  document.getElementById('calendarLinkDisplay').style.display = 'block';
}
```

## Security Considerations

### ✅ Safe Practices

- Tokens are cryptographically random (32 bytes)
- Hashed before storage (SHA-256)
- User can only see their own shifts
- Published-only filter prevents leaking draft rotas
- Tokens are revocable/rotatable
- No PINs or personal data in feed

### ⚠️ User Responsibilities

- **Keep token private**: Anyone with URL can see published shifts
- **Revoke if shared**: Generate new token to invalidate old URL
- **Use HTTPS**: Don't share over insecure channels

## Monitoring

### Track Usage

```sql
-- Recently used tokens
SELECT 
  u.name,
  ct.last_used_at,
  ct.created_at
FROM calendar_tokens ct
JOIN users u ON u.id = ct.user_id
WHERE ct.revoked_at IS NULL
ORDER BY ct.last_used_at DESC NULLS LAST;

-- Inactive tokens (never used)
SELECT 
  u.name,
  ct.created_at,
  EXTRACT(days FROM now() - ct.created_at) as days_old
FROM calendar_tokens ct
JOIN users u ON u.id = ct.user_id
WHERE ct.revoked_at IS NULL
  AND ct.last_used_at IS NULL
  AND ct.created_at < now() - interval '7 days';
```

### Revoke Stale Tokens

```sql
-- Revoke tokens unused for 90 days
UPDATE calendar_tokens
SET revoked_at = now()
WHERE revoked_at IS NULL
  AND (
    last_used_at < now() - interval '90 days'
    OR (last_used_at IS NULL AND created_at < now() - interval '90 days')
  );
```

## Troubleshooting

### Feed Not Updating

- Calendar apps poll every 1-24 hours (not real-time)
- Force refresh: Remove subscription and re-add
- Check `last_used_at` timestamp in DB

### Events Show Wrong Times

- Edge function uses UTC timestamps
- Calendar app converts to device timezone
- Verify `shifts.start_time` is correct in DB

### Overnight Shifts Span Two Days

- This is correct behavior
- If `end_time < start_time`, event ends next day
- Example: 20:00-08:00 Night shift

## Future Enhancements

- [ ] Add `webcal://` URL builder in UI
- [ ] Token expiry (e.g., 1 year auto-revoke)
- [ ] Email notification when token used from new IP
- [ ] Include shift comments in DESCRIPTION (published-visible only)
- [ ] Add ALARM reminder (configurable hours before shift)
- [ ] Timezone selection per user (currently Europe/Madrid)

## References

- RFC 5545: iCalendar specification
- Supabase Edge Functions: https://supabase.com/docs/guides/functions
- ICS validators: https://icalendar.org/validator.html

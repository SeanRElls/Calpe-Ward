# Calendar Subscription - Deployment & Testing

## Quick Deployment

### 1. Deploy Database Changes

Run the migration in your Supabase SQL editor or via CLI:

```bash
# Option A: Via SQL Editor
# Copy/paste contents of sql/migrations/2026-01-20-calendar-tokens.sql

# Option B: Via Supabase CLI
supabase db push
```

### 2. Deploy Edge Function

```bash
# Ensure Supabase CLI is installed and logged in
supabase login

# Link to your project (if not already linked)
supabase link --project-ref <your-project-ref>

# Deploy the ICS function
supabase functions deploy ics

# Verify deployment
supabase functions list
```

### 3. Verify Edge Function Environment

The Edge Function needs these environment variables (automatically available):
- `SUPABASE_URL` - Your project URL
- `SUPABASE_SERVICE_ROLE_KEY` - Service role key for RPC calls

These are automatically injected by Supabase. No manual configuration needed.

---

## Testing

### Test 1: Generate Token (Requires Active Session)

```bash
# Replace with your values
PROJECT_URL="https://pxpjxyfcydiasrycpbfp.supabase.co"
ANON_KEY="your-anon-key"
SESSION_TOKEN="your-session-token"  # From currentToken in browser

# Generate calendar token
curl -X POST "$PROJECT_URL/rest/v1/rpc/generate_calendar_token" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"p_token\": \"$SESSION_TOKEN\"}"

# Expected response:
# {
#   "success": true,
#   "token": "64-character-hex-string...",
#   "message": "Calendar token generated. Save this token - it will not be shown again."
# }

# Save the token value for next test
```

### Test 2: Fetch Calendar Feed

```bash
# Use the token from Test 1
CALENDAR_TOKEN="your-64-char-token-from-test-1"

# Fetch ICS feed
curl -i "$PROJECT_URL/functions/v1/ics?token=$CALENDAR_TOKEN"

# Expected response:
# HTTP/1.1 200 OK
# Content-Type: text/calendar; charset=utf-8
# Content-Disposition: attachment; filename="calpe-ward-shifts.ics"
# Cache-Control: private, max-age=300
# 
# BEGIN:VCALENDAR
# VERSION:2.0
# PRODID:-//Calpe Ward//Shift Calendar//EN
# CALSCALE:GREGORIAN
# METHOD:PUBLISH
# ...
# BEGIN:VEVENT
# UID:shift-12345@calpeward
# DTSTAMP:20260120T120000Z
# DTSTART:20260121T060000Z
# DTEND:20260121T140000Z
# SUMMARY:D - Day Shift
# DESCRIPTION:Hours: 06:00 – 14:00
# LOCATION:Calpe Ward
# STATUS:CONFIRMED
# TRANSP:OPAQUE
# END:VEVENT
# ...
# END:VCALENDAR
```

### Test 3: Invalid Token

```bash
# Test with invalid token
curl -i "$PROJECT_URL/functions/v1/ics?token=invalidtoken"

# Expected response:
# HTTP/1.1 401 Unauthorized
# Content-Type: text/plain
# 
# Invalid or revoked calendar token
```

### Test 4: Missing Token

```bash
# Test without token parameter
curl -i "$PROJECT_URL/functions/v1/ics"

# Expected response:
# HTTP/1.1 401 Unauthorized
# Content-Type: text/plain
# 
# Missing token parameter
```

### Test 5: Revoke Token

```bash
# Revoke the token
curl -X POST "$PROJECT_URL/rest/v1/rpc/revoke_calendar_token" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"p_token\": \"$SESSION_TOKEN\"}"

# Expected response:
# {
#   "success": true,
#   "revoked_count": 1,
#   "message": "Calendar token revoked"
# }

# Now test that the calendar feed is disabled
curl -i "$PROJECT_URL/functions/v1/ics?token=$CALENDAR_TOKEN"

# Should return 401 - Invalid or revoked
```

---

## Browser Testing

### Via Frontend UI

1. **Login** to rota.html or requests.html
2. **Click** your account badge (top-right corner)
3. **Scroll** to "📅 Calendar Subscription" section
4. **Click** "Generate Calendar Link"
5. **Copy** the HTTPS URL or webcal:// URL
6. **Add** to your calendar app:

#### Apple Calendar
1. File → New Calendar Subscription
2. Paste the `webcal://...` URL
3. Click Subscribe
4. Choose update frequency (e.g., every hour)

#### Google Calendar
1. Settings → Add calendar → From URL
2. Paste the `https://...` URL
3. Click Add calendar
4. Wait a few minutes for sync

#### Outlook
1. Add calendar → Subscribe from web
2. Paste the URL
3. Click Import

---

## Validation Checklist

After deployment, verify:

- [ ] Database migration applied successfully
  - [ ] `calendar_tokens` table exists
  - [ ] RPCs created: `generate_calendar_token`, `revoke_calendar_token`, `get_published_shifts_for_calendar`
  - [ ] RLS policies active on `calendar_tokens`

- [ ] Edge Function deployed
  - [ ] Listed in `supabase functions list`
  - [ ] Returns 401 for invalid tokens
  - [ ] Returns valid ICS for valid tokens

- [ ] Frontend UI visible
  - [ ] Calendar section appears in account modal
  - [ ] "Generate Calendar Link" button works
  - [ ] URLs display after generation
  - [ ] Copy buttons work
  - [ ] "Revoke Link" button works

- [ ] Data correctness
  - [ ] Only published shifts appear in feed
  - [ ] Only user's own shifts appear
  - [ ] Shift codes/labels match database
  - [ ] Times are correct (check overnight shifts)
  - [ ] Events have stable UIDs

- [ ] Calendar app integration
  - [ ] Subscription URL accepted by calendar app
  - [ ] Events appear in calendar
  - [ ] Events update when rota changes
  - [ ] Past shifts included (30 days)
  - [ ] Future shifts included

---

## Troubleshooting

### "Failed to generate token"

**Cause:** Session token invalid or RPC not deployed

**Fix:**
1. Verify user is logged in (`window.currentToken` exists)
2. Check RPC exists: `SELECT * FROM pg_proc WHERE proname = 'generate_calendar_token'`
3. Check RPC permissions: `GRANT EXECUTE ON FUNCTION generate_calendar_token TO authenticated`

### "Invalid or revoked calendar token" when fetching feed

**Cause:** Token doesn't exist or was revoked

**Fix:**
1. Generate new token via UI
2. Check token exists: `SELECT * FROM calendar_tokens WHERE revoked_at IS NULL`
3. Verify token matches (hash comparison)

### Empty calendar / No events

**Cause:** No published shifts or date filter too narrow

**Fix:**
1. Check assignments exist: `SELECT * FROM rota_assignments WHERE user_id = ? AND status = 'published'`
2. Verify date range: RPC includes past 30 days + future
3. Check shift join: Ensure `shifts` table has matching records

### Events show wrong times

**Cause:** Timezone mismatch or overnight shift calculation

**Fix:**
1. Verify `shifts.start_time` and `end_time` in database
2. Check Edge Function date math (overnight shifts add 1 day to end)
3. Calendar app converts UTC to local time automatically

### "Function not found" when deploying

**Cause:** Supabase CLI not linked to project

**Fix:**
```bash
supabase link --project-ref <your-project-ref>
supabase functions deploy ics
```

### Last_used_at not updating

**Cause:** RPC update fails silently (by design)

**Fix:**
- This is non-critical; wrapped in exception handler
- Check for database connection issues
- Verify user still has active token

---

## Performance Notes

### Edge Function
- **Cold start**: ~200ms (first request after idle)
- **Warm**: ~50-100ms
- **Caching**: 5 minutes (client-side)

### Database Query
- Indexed on `token_hash` (fast lookup)
- Indexed on `user_id` + `revoked_at` (fast validation)
- Query returns 30 days past + all future (~50-200 shifts max per user)

### Calendar Client Polling
- Most apps poll every 1-24 hours
- Force refresh by re-subscribing
- Not real-time (by design)

---

## Monitoring Queries

### Active tokens by user

```sql
SELECT 
  u.name,
  ct.created_at,
  ct.last_used_at,
  EXTRACT(days FROM now() - ct.last_used_at) as days_since_use
FROM calendar_tokens ct
JOIN users u ON u.id = ct.user_id
WHERE ct.revoked_at IS NULL
ORDER BY ct.last_used_at DESC NULLS LAST;
```

### Unused tokens (potential cleanup)

```sql
SELECT 
  u.name,
  ct.created_at,
  EXTRACT(days FROM now() - ct.created_at) as age_days
FROM calendar_tokens ct
JOIN users u ON u.id = ct.user_id
WHERE ct.revoked_at IS NULL
  AND ct.last_used_at IS NULL
  AND ct.created_at < now() - interval '30 days'
ORDER BY ct.created_at;
```

### Recent calendar feed requests (check Edge Function logs)

```bash
# Via Supabase Dashboard
# Functions → ics → Logs

# Or via CLI
supabase functions logs ics --tail
```

---

## Security Audit

### ✅ Safe Practices Implemented

- Tokens are 32-byte cryptographically random values
- Tokens hashed (SHA-256) before database storage
- RLS policies prevent cross-user access
- Published-only filter (no draft leaks)
- Tokens revocable/rotatable without re-login
- Service role key never exposed to client
- No PINs or sensitive data in feed

### ⚠️ User Responsibilities

- Keep subscription URL private
- Revoke token if shared accidentally
- Don't share calendar subscription with others
- Use HTTPS, not HTTP

### 🔒 Admin Best Practices

- Monitor `last_used_at` for suspicious patterns
- Auto-revoke stale tokens (e.g., 90+ days unused)
- Log token generation/revocation in audit trail (future enhancement)
- Rate-limit token generation (future enhancement)

---

## Next Steps / Future Enhancements

- [ ] Add token expiry (e.g., 1 year auto-revoke)
- [ ] Email notification on first use from new IP
- [ ] Include shift comments (published-visible only) in DESCRIPTION
- [ ] Add ALARM/reminder (configurable hours before shift)
- [ ] Timezone selection per user (currently UTC)
- [ ] Rate limiting on token generation
- [ ] Audit log for token generation/usage
- [ ] Admin view: see who has active calendar subscriptions

---

## Support

For issues or questions:
1. Check Supabase Edge Function logs
2. Verify database migration applied
3. Test with curl commands above
4. Validate ICS output: https://icalendar.org/validator.html

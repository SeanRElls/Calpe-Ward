# Clean RPC Inventory: Approved Token-Only Functions
**Date:** January 16, 2026  
**Status:** ✅ APPROVED FOR PRODUCTION USE  
**Total Functions:** 56 token-based RPCs  

---

## Session Management (4 functions)

### require_session_permissions
**Signature:** `require_session_permissions(p_token uuid, p_required_permissions text[] DEFAULT NULL)`  
**Returns:** `uuid` (user_id)  
**Purpose:** Core authentication - validates session token and checks permissions  
**Permission:** N/A (internal validator)  
**Admin Bypass:** Yes (admins skip permission check)  

**Usage:**
```javascript
// Internal - called by other RPCs
v_uid := public.require_session_permissions(p_token, ARRAY['manage_shifts']);
```

---

### validate_session
**Signature:** `validate_session(p_token uuid)`  
**Returns:** `TABLE(valid boolean, user_id uuid, error_message text)`  
**Purpose:** Check if session token is valid (not expired/revoked)  
**Permission:** N/A (read-only check)  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('validate_session', {
  p_token: currentToken
});
if (data[0]?.valid) {
  console.log('Session valid for user:', data[0].user_id);
}
```

---

### revoke_session
**Signature:** `revoke_session(p_token uuid)`  
**Returns:** `void`  
**Purpose:** Immediately invalidate session token (logout)  
**Permission:** N/A (users can revoke own session)  

**Usage:**
```javascript
await supabaseClient.rpc('revoke_session', {
  p_token: currentToken
});
// Token now invalid, redirect to login
```

---

### verify_login
**Signature:** `verify_login(p_username text, p_pin text, p_ip_hash text DEFAULT 'unknown', p_user_agent_hash text DEFAULT 'unknown')`  
**Returns:** `TABLE(token uuid, user_id uuid, username text, error_message text)`  
**Purpose:** Authenticate user with username + PIN, create session token  
**Permission:** N/A (public login endpoint)  
**Rate Limit:** 5 failed attempts → 15 min lockout  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('verify_login', {
  p_username: 'john.doe',
  p_pin: '1234',
  p_ip_hash: await hashString(ipAddress),
  p_user_agent_hash: await hashString(navigator.userAgent)
});

if (data[0]?.token) {
  sessionStorage.setItem('session_token', data[0].token);
  window.location.href = '/rota.html';
}
```

---

## Staff Functions (13 functions)

### ack_notice
**Signature:** `ack_notice(p_token uuid, p_notice_id uuid, p_version integer)`  
**Returns:** `void`  
**Purpose:** Mark notice as acknowledged by current user  
**Permission:** N/A (staff can ack own notices)  

**Usage:**
```javascript
await supabaseClient.rpc('ack_notice', {
  p_token: currentToken,
  p_notice_id: noticeId,
  p_version: 1
});
```

---

### acknowledge_notice
**Signature:** `acknowledge_notice(p_token uuid, p_notice_id uuid)`  
**Returns:** `void`  
**Purpose:** Mark notice as acknowledged (no version tracking)  
**Permission:** N/A (staff can ack own notices)  

**Usage:**
```javascript
await supabaseClient.rpc('acknowledge_notice', {
  p_token: currentToken,
  p_notice_id: noticeId
});
```

---

### change_user_pin
**Signature:** `change_user_pin(p_token uuid, p_old_pin text, p_new_pin text)`  
**Returns:** `void`  
**Purpose:** Change current user's PIN (requires old PIN verification)  
**Permission:** N/A (users can change own PIN)  

**Usage:**
```javascript
await supabaseClient.rpc('change_user_pin', {
  p_token: currentToken,
  p_old_pin: '1234',
  p_new_pin: '5678'
});
```

---

### clear_request_cell
**Signature:** `clear_request_cell(p_token uuid, p_date date)`  
**Returns:** `void`  
**Purpose:** Delete current user's off-duty request for specified date  
**Permission:** N/A (users can delete own requests)  

**Usage:**
```javascript
await supabaseClient.rpc('clear_request_cell', {
  p_token: currentToken,
  p_date: '2026-01-20'
});
```

---

### get_notices_for_user
**Signature:** `get_notices_for_user(p_token uuid)`  
**Returns:** `TABLE(id uuid, title text, body_en text, body_es text, version integer, is_active boolean, updated_at timestamptz, created_by uuid, created_by_name text, target_all boolean, target_roles integer[], acknowledged_at timestamptz, ack_version integer)`  
**Purpose:** Get all active notices for current user (filtered by role)  
**Permission:** N/A (read-only, filtered by user's role)  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('get_notices_for_user', {
  p_token: currentToken
});
// Returns notices targeted to user's role
```

---

### get_pending_swap_requests_for_me
**Signature:** `get_pending_swap_requests_for_me(p_token uuid)`  
**Returns:** `TABLE(id uuid, initiator_name text, counterparty_name text, initiator_shift_date date, initiator_shift_code text, counterparty_shift_date date, counterparty_shift_code text, created_at timestamptz)`  
**Purpose:** Get swap requests where current user is the counterparty  
**Permission:** N/A (filtered to current user)  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('get_pending_swap_requests_for_me', {
  p_token: currentToken
});
// Returns swap requests awaiting user's response
```

---

### get_unread_notices
**Signature:** `get_unread_notices(p_token uuid)`  
**Returns:** `TABLE(id uuid, created_at timestamptz, updated_at timestamptz, title text, body_en text, body_es text, target_role_id integer)`  
**Purpose:** Get unacknowledged notices for current user  
**Permission:** N/A (filtered to current user)  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('get_unread_notices', {
  p_token: currentToken
});
```

---

### get_week_comments
**Signature:** `get_week_comments(p_token uuid, p_week_id uuid)`  
**Returns:** `TABLE(user_id uuid, comment text)`  
**Purpose:** Get all week comments for specified week  
**Permission:** N/A (read-only)  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('get_week_comments', {
  p_token: currentToken,
  p_week_id: weekId
});
```

---

### set_request_cell
**Signature:** `set_request_cell(p_token uuid, p_date date, p_value text, p_important_rank smallint DEFAULT NULL)`  
**Returns:** `TABLE(out_id uuid, out_user_id uuid, out_date date, out_value text, out_important_rank smallint)`  
**Purpose:** Create/update off-duty request for current user  
**Permission:** N/A (users can set own requests)  
**Validation:** Max 5 requests per week (enforced by trigger)  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('set_request_cell', {
  p_token: currentToken,
  p_date: '2026-01-20',
  p_value: 'OFF',
  p_important_rank: 1
});
```

---

### set_user_language
**Signature:** `set_user_language(p_token uuid, p_lang text)`  
**Returns:** `text` (new language)  
**Purpose:** Set current user's preferred language (en/es)  
**Permission:** N/A (users can set own preference)  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('set_user_language', {
  p_token: currentToken,
  p_lang: 'es'
});
```

---

### staff_request_shift_swap
**Signature:** `staff_request_shift_swap(p_token uuid, p_initiator_shift_date date, p_counterparty_user_id uuid, p_counterparty_shift_date date, p_period_id integer DEFAULT NULL)`  
**Returns:** `TABLE(success boolean, swap_request_id uuid, error_message text)`  
**Purpose:** Request shift swap with another user  
**Permission:** N/A (staff can request own swaps)  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('staff_request_shift_swap', {
  p_token: currentToken,
  p_initiator_shift_date: '2026-01-20',
  p_counterparty_user_id: otherUserId,
  p_counterparty_shift_date: '2026-01-21',
  p_period_id: null  // Uses active period
});

if (data[0]?.success) {
  console.log('Swap request created:', data[0].swap_request_id);
}
```

---

### staff_respond_to_swap_request
**Signature:** `staff_respond_to_swap_request(p_token uuid, p_swap_request_id uuid, p_response text)`  
**Returns:** `TABLE(success boolean, error_message text)`  
**Purpose:** Accept/decline swap request where current user is counterparty  
**Permission:** N/A (staff can respond to own swap requests)  
**Valid Responses:** 'accept', 'decline'  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('staff_respond_to_swap_request', {
  p_token: currentToken,
  p_swap_request_id: swapRequestId,
  p_response: 'accept'
});
```

---

### upsert_week_comment
**Signature:** `upsert_week_comment(p_token uuid, p_week_id uuid, p_user_id uuid, p_comment text)`  
**Returns:** `TABLE(user_id uuid, week_id uuid, comment text)`  
**Purpose:** Add/update comment for user on specific week  
**Permission:** N/A (users can comment on own weeks)  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('upsert_week_comment', {
  p_token: currentToken,
  p_week_id: weekId,
  p_user_id: currentUserId,
  p_comment: 'On annual leave'
});
```

---

## Admin Functions (24 functions)

### admin_approve_swap_request
**Signature:** `admin_approve_swap_request(p_token uuid, p_swap_request_id uuid)`  
**Returns:** `TABLE(success boolean, swap_execution_id uuid, error_message text)`  
**Purpose:** Admin approves swap request and executes shift swap  
**Permission:** `manage_shifts` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('admin_approve_swap_request', {
  p_token: adminToken,
  p_swap_request_id: swapRequestId
});

if (data[0]?.success) {
  console.log('Swap executed:', data[0].swap_execution_id);
}
```

---

### admin_clear_request_cell
**Signature:** `admin_clear_request_cell(p_token uuid, p_target_user_id uuid, p_date date)`  
**Returns:** `void`  
**Purpose:** Admin deletes off-duty request for any user  
**Permission:** `requests.edit` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
await supabaseClient.rpc('admin_clear_request_cell', {
  p_token: adminToken,
  p_target_user_id: userId,
  p_date: '2026-01-20'
});
```

---

### admin_create_five_week_period
**Signature:** `admin_create_five_week_period(p_token uuid, p_name text, p_start_date date, p_end_date date)`  
**Returns:** `uuid` (period_id)  
**Purpose:** Create new 5-week rota period with weeks and dates  
**Permission:** `periods.create` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('admin_create_five_week_period', {
  p_token: adminToken,
  p_name: 'Period 2026-02',
  p_start_date: '2026-02-01',
  p_end_date: '2026-03-07'
});
// Returns new period UUID
```

---

### admin_decline_swap_request
**Signature:** `admin_decline_swap_request(p_token uuid, p_swap_request_id uuid)`  
**Returns:** `TABLE(success boolean, error_message text)`  
**Purpose:** Admin declines swap request without executing  
**Permission:** `manage_shifts` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('admin_decline_swap_request', {
  p_token: adminToken,
  p_swap_request_id: swapRequestId
});
```

---

### admin_delete_notice
**Signature:** `admin_delete_notice(p_token uuid, p_notice_id uuid)`  
**Returns:** `void`  
**Purpose:** Delete notice and all acknowledgments  
**Permission:** `notices.delete` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
await supabaseClient.rpc('admin_delete_notice', {
  p_token: adminToken,
  p_notice_id: noticeId
});
```

---

### admin_execute_shift_swap
**Signature:** `admin_execute_shift_swap(p_token uuid, p_initiator_user_id uuid, p_initiator_shift_date date, p_counterparty_user_id uuid, p_counterparty_shift_date date, p_period_id integer DEFAULT NULL)`  
**Returns:** `TABLE(success boolean, swap_execution_id uuid, error_message text)`  
**Purpose:** Admin directly swaps shifts between two users (no request needed)  
**Permission:** `manage_shifts` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('admin_execute_shift_swap', {
  p_token: adminToken,
  p_initiator_user_id: userId1,
  p_initiator_shift_date: '2026-01-20',
  p_counterparty_user_id: userId2,
  p_counterparty_shift_date: '2026-01-21',
  p_period_id: null
});
```

---

### admin_get_all_notices
**Signature:** `admin_get_all_notices(p_token uuid)`  
**Returns:** `TABLE(notice_id uuid, title text, body_en text, body_es text, version integer, is_active boolean, updated_at timestamptz, created_by_name text, target_all boolean, target_roles integer[])`  
**Purpose:** Get all notices (active + inactive) with metadata  
**Permission:** `notices.view` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('admin_get_all_notices', {
  p_token: adminToken
});
// Returns all notices including drafts
```

---

### admin_get_notice_acks
**Signature:** `admin_get_notice_acks(p_token uuid, p_notice_id uuid)`  
**Returns:** `TABLE(acked jsonb, pending jsonb)`  
**Purpose:** Get acknowledgment status for notice (who acked, who pending)  
**Permission:** `notices.view` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('admin_get_notice_acks', {
  p_token: adminToken,
  p_notice_id: noticeId
});
// data[0].acked = [{user_id, name, acked_at}, ...]
// data[0].pending = [{user_id, name}, ...]
```

---

### admin_get_swap_requests
**Signature:** `admin_get_swap_requests(p_token uuid)`  
**Returns:** `TABLE(id uuid, period_id integer, initiator_name text, counterparty_name text, initiator_shift_date date, initiator_shift_code text, counterparty_shift_date date, counterparty_shift_code text, status text, counterparty_response text, counterparty_responded_at timestamp, created_at timestamp)`  
**Purpose:** Get all swap requests for admin review  
**Permission:** `manage_shifts` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('admin_get_swap_requests', {
  p_token: adminToken
});
```

---

### admin_lock_request_cell
**Signature:** `admin_lock_request_cell(p_token uuid, p_target_user_id uuid, p_date date, p_reason_en text DEFAULT NULL, p_reason_es text DEFAULT NULL)`  
**Returns:** `request_cell_locks` (row)  
**Purpose:** Lock user's request cell (prevent changes) with optional reason  
**Permission:** `requests.lock` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('admin_lock_request_cell', {
  p_token: adminToken,
  p_target_user_id: userId,
  p_date: '2026-01-20',
  p_reason_en: 'Already scheduled',
  p_reason_es: 'Ya programado'
});
```

---

### admin_notice_ack_counts
**Signature:** `admin_notice_ack_counts(p_token uuid, p_notice_ids uuid[])`  
**Returns:** `TABLE(notice_id uuid, acked_count bigint, pending_count bigint)`  
**Purpose:** Get acknowledgment counts for multiple notices  
**Permission:** `notices.view` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('admin_notice_ack_counts', {
  p_token: adminToken,
  p_notice_ids: [noticeId1, noticeId2, noticeId3]
});
// Returns counts for each notice
```

---

### admin_set_active_period
**Signature:** `admin_set_active_period(p_token uuid, p_period_id uuid)`  
**Returns:** `void`  
**Purpose:** Set specified period as active (deactivates all others)  
**Permission:** `periods.set_active` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
await supabaseClient.rpc('admin_set_active_period', {
  p_token: adminToken,
  p_period_id: periodId
});
```

---

### admin_set_notice_active
**Signature:** `admin_set_notice_active(p_token uuid, p_notice_id uuid, p_active boolean)`  
**Returns:** `void`  
**Purpose:** Activate/deactivate notice (show/hide from users)  
**Permission:** `notices.edit` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
await supabaseClient.rpc('admin_set_notice_active', {
  p_token: adminToken,
  p_notice_id: noticeId,
  p_active: true
});
```

---

### admin_set_period_closes_at
**Signature:** `admin_set_period_closes_at(p_token uuid, p_period_id uuid, p_closes_at timestamptz)`  
**Returns:** `void`  
**Purpose:** Set deadline for off-duty requests for period  
**Permission:** `periods.edit` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
await supabaseClient.rpc('admin_set_period_closes_at', {
  p_token: adminToken,
  p_period_id: periodId,
  p_closes_at: '2026-01-15T17:00:00Z'
});
```

---

### admin_set_period_hidden
**Signature:** `admin_set_period_hidden(p_token uuid, p_period_id uuid, p_hidden boolean)`  
**Returns:** `void`  
**Purpose:** Hide/unhide period from staff view  
**Permission:** `periods.edit` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
await supabaseClient.rpc('admin_set_period_hidden', {
  p_token: adminToken,
  p_period_id: periodId,
  p_hidden: false
});
```

---

### admin_set_request_cell
**Signature:** `admin_set_request_cell(p_token uuid, p_target_user_id uuid, p_date date, p_value text, p_important_rank smallint DEFAULT NULL)`  
**Returns:** `TABLE(out_id uuid, out_user_id uuid, out_date date, out_value text, out_important_rank smallint)`  
**Purpose:** Admin sets off-duty request for any user  
**Permission:** `requests.edit` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('admin_set_request_cell', {
  p_token: adminToken,
  p_target_user_id: userId,
  p_date: '2026-01-20',
  p_value: 'OFF',
  p_important_rank: 2
});
```

---

### admin_set_week_open_flags
**Signature:** `admin_set_week_open_flags(p_token uuid, p_week_id uuid, p_open boolean, p_open_after_close boolean)`  
**Returns:** `void`  
**Purpose:** Set week open/closed for requests  
**Permission:** `weeks.edit` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
await supabaseClient.rpc('admin_set_week_open_flags', {
  p_token: adminToken,
  p_week_id: weekId,
  p_open: true,
  p_open_after_close: false
});
```

---

### admin_toggle_hidden_period
**Signature:** `admin_toggle_hidden_period(p_token uuid, p_period_id uuid)`  
**Returns:** `void`  
**Purpose:** Toggle period hidden status (show/hide from staff)  
**Permission:** `periods.edit` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
await supabaseClient.rpc('admin_toggle_hidden_period', {
  p_token: adminToken,
  p_period_id: periodId
});
```

---

### admin_unlock_request_cell
**Signature:** `admin_unlock_request_cell(p_token uuid, p_target_user_id uuid, p_date date)`  
**Returns:** `void`  
**Purpose:** Remove lock from request cell (allow user to change)  
**Permission:** `requests.lock` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
await supabaseClient.rpc('admin_unlock_request_cell', {
  p_token: adminToken,
  p_target_user_id: userId,
  p_date: '2026-01-20'
});
```

---

### admin_upsert_notice
**Signature:** `admin_upsert_notice(p_token uuid, p_notice_id uuid, p_title text, p_body_en text, p_body_es text, p_target_all boolean, p_target_roles integer[])`  
**Returns:** `uuid` (notice_id)  
**Purpose:** Create new notice or update existing  
**Permission:** `notices.create` (if p_notice_id IS NULL), `notices.edit` (if exists) - unless is_admin=true  
**Admin Bypass:** Yes  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('admin_upsert_notice', {
  p_token: adminToken,
  p_notice_id: null,  // null = create new
  p_title: 'Important Announcement',
  p_body_en: 'Staff meeting on Monday',
  p_body_es: 'Reunión de personal el lunes',
  p_target_all: true,
  p_target_roles: []
});
// Returns notice UUID
```

---

### admin_upsert_user
**Signature:** `admin_upsert_user(p_token uuid, p_user_id uuid, p_name text, p_role_id integer)`  
**Returns:** `uuid` (user_id)  
**Purpose:** Create new user or update existing user's name/role  
**Permission:** `users.create` (if p_user_id IS NULL), `users.edit` (if exists) - unless is_admin=true  
**Admin Bypass:** Yes  

**Usage:**
```javascript
const { data, error } = await supabaseClient.rpc('admin_upsert_user', {
  p_token: adminToken,
  p_user_id: null,  // null = create new
  p_name: 'John Doe',
  p_role_id: 2
});
// Returns user UUID
```

---

### set_user_active
**Signature:** `set_user_active(p_token uuid, p_user_id uuid, p_active boolean)`  
**Returns:** `void`  
**Purpose:** Activate/deactivate user account (soft delete)  
**Permission:** `users.edit` (unless is_admin=true)  
**Admin Bypass:** Yes  

**Usage:**
```javascript
await supabaseClient.rpc('set_user_active', {
  p_token: adminToken,
  p_user_id: userId,
  p_active: false  // Deactivate user
});
```

---

## Permission Keys Reference

| Permission Key | Grants Access To | Function Examples |
|---------------|------------------|-------------------|
| `manage_shifts` | Swap requests, shift swaps | admin_approve_swap_request, admin_execute_shift_swap |
| `notices.create` | Create notices | admin_upsert_notice (new) |
| `notices.edit` | Edit existing notices | admin_upsert_notice (update), admin_set_notice_active |
| `notices.delete` | Delete notices | admin_delete_notice |
| `notices.view` | View all notices (admin panel) | admin_get_all_notices, admin_get_notice_acks |
| `periods.create` | Create new periods | admin_create_five_week_period |
| `periods.edit` | Modify periods | admin_set_period_hidden, admin_set_period_closes_at |
| `periods.set_active` | Set active period | admin_set_active_period |
| `requests.edit` | Edit any user's requests | admin_set_request_cell, admin_clear_request_cell |
| `requests.lock` | Lock/unlock request cells | admin_lock_request_cell, admin_unlock_request_cell |
| `users.create` | Create new users | admin_upsert_user (new) |
| `users.edit` | Edit existing users | admin_upsert_user (update), set_user_active |
| `weeks.edit` | Open/close weeks | admin_set_week_open_flags |

**Note:** Users with `is_admin=true` bypass ALL permission checks.

---

## Best Practices

### 1. Token Management
```javascript
// Store token in sessionStorage (not localStorage - expires on tab close)
sessionStorage.setItem('session_token', token);

// Always pass token to RPCs
const currentToken = sessionStorage.getItem('session_token');
await supabaseClient.rpc('function_name', {
  p_token: currentToken,
  // ... other params
});

// Clear token on logout
sessionStorage.removeItem('session_token');
await supabaseClient.rpc('revoke_session', { p_token: currentToken });
```

### 2. Error Handling
```javascript
const { data, error } = await supabaseClient.rpc('ack_notice', {
  p_token: currentToken,
  p_notice_id: noticeId,
  p_version: 1
});

if (error) {
  if (error.message.includes('Invalid or expired session')) {
    // Redirect to login
    window.location.href = '/login.html';
  } else if (error.message.includes('Insufficient permissions')) {
    // Show permission denied message
    alert('You do not have permission to perform this action');
  } else {
    // Generic error
    console.error('RPC error:', error);
  }
}
```

### 3. Permission Checking
```javascript
// Validate session before accessing admin pages
const { data, error } = await supabaseClient.rpc('validate_session', {
  p_token: currentToken
});

if (!data[0]?.valid) {
  window.location.href = '/login.html';
  return;
}

// Check if admin (for UI rendering)
const { data: user } = await supabaseClient
  .from('users')
  .select('is_admin')
  .eq('id', data[0].user_id)
  .single();

if (user?.is_admin) {
  // Show admin UI
}
```

### 4. Rate Limiting Awareness
```javascript
// verify_login has rate limiting: 5 failed attempts → 15 min lockout
// Show helpful error to user
if (data[0]?.error_message?.includes('locked')) {
  alert('Too many failed login attempts. Please try again in 15 minutes.');
}
```

---

## Migration Notes

### Deprecated Functions (DO NOT USE)

| Old Function | Status | Replacement |
|-------------|--------|-------------|
| `verify_user_pin(p_user_id, p_pin)` | ❌ REMOVED | `change_user_pin(p_token, p_old_pin, p_new_pin)` |
| `set_user_pin(p_user_id, p_pin)` | ❌ REMOVED | Create `admin_set_user_pin(p_token, p_target_user_id, p_new_pin)` |
| `admin_create_next_period(p_admin_user_id)` | ❌ REMOVED | `admin_create_five_week_period(p_token, ...)` |
| `admin_set_active_period(p_admin_user_id, bigint)` | ❌ REMOVED | `admin_set_active_period(p_token, uuid)` |
| `admin_set_period_hidden(p_admin_user_id, bigint, boolean)` | ❌ REMOVED | `admin_set_period_hidden(p_token, uuid, boolean)` |
| `admin_set_week_open(p_admin_user_id, bigint, boolean)` | ❌ REMOVED | `admin_set_week_open_flags(p_token, uuid, boolean, boolean)` |

### Direct Table Access (DO NOT USE)

```javascript
// ❌ WRONG - Direct table access will fail with GRANT revocation
await supabaseClient.from('sessions').insert({...});
await supabaseClient.from('users').update({...});
await supabaseClient.from('requests').delete().eq('id', id);

// ✅ CORRECT - Use RPCs
await supabaseClient.rpc('set_request_cell', { p_token, p_date, p_value });
await supabaseClient.rpc('clear_request_cell', { p_token, p_date });
```

**Allowed Direct Reads:**
```javascript
// ✅ OK - SELECT on reference tables
const { data } = await supabaseClient.from('roles').select('*');
const { data } = await supabaseClient.from('shifts').select('*');
```

---

**End of Inventory**

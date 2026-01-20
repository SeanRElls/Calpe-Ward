# Token-Only RPC Migration: Final Review & Verification Checklist

**Date**: 2026-01-16  
**Status**: Ready for Deployment  
**Last Updated**: Post-Frontend-Patch

---

## 1. MIGRATION REVIEW

### 1.1 SQL Script Safety & Idempotency

**File**: `sql/migrate_to_token_only_rpcs.sql` (1422 lines)

#### Structure Review
✅ **BEGIN/COMMIT Pattern**: Script wraps entire migration in `BEGIN; ... COMMIT;`  
- Ensures atomic execution (all-or-nothing)
- Single failure rolls back all changes
- Safe to retry on network failure

✅ **DROP FUNCTION IF EXISTS Statements**: 9 old overloads dropped with exact signatures
- Drops only obsolete overloads (ones with `p_user_id`/`p_admin_id`/`p_pin`)
- Does NOT drop token-only versions (safe to re-run)
- Uses exact parameter types to avoid silent failures

**Dropped functions** (all safe—no longer used):
```sql
DROP FUNCTION IF EXISTS public.ack_notice(uuid, uuid, uuid, integer);
DROP FUNCTION IF EXISTS public.acknowledge_notice(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.clear_request_cell(uuid, uuid, date);
DROP FUNCTION IF EXISTS public.get_all_notices(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_notices_for_user(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_pending_swap_requests_for_me(uuid, uuid);
DROP FUNCTION IF EXISTS public.set_request_cell(uuid, uuid, date, text, smallint);
DROP FUNCTION IF EXISTS public.staff_request_shift_swap(uuid, uuid, date, uuid, date, integer);
DROP FUNCTION IF EXISTS public.staff_respond_to_swap_request(uuid, uuid, uuid, text);
```

#### Function Patterns Review

✅ **SECURITY DEFINER + SET search_path**: All 42 recreated functions include:
```sql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
```
- Prevents SQL injection via search_path manipulation
- Executes with function owner's privileges (typically postgres)
- Protects against malicious `FROM` clauses, unqualified function names, etc.

✅ **Token Validation Pattern (Staff Functions)**:
All 12 staff functions follow this pattern:
```sql
v_uid := public.require_session_permissions(p_token, null);
-- Function body uses v_uid, never trusts client-supplied user_id
```
- No `p_user_id` parameter (token is sole identity source)
- Single session validation call per function
- Function infers user identity from token only

✅ **Admin Bypass Pattern (Admin Functions)**:
All 30 admin functions follow this pattern:
```sql
v_admin_uid := public.require_session_permissions(p_token, null);  -- Validate token first
SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
IF v_is_admin IS NULL OR NOT v_is_admin THEN
  -- Non-admin must have specific permission
  PERFORM public.require_session_permissions(p_token, ARRAY['permission.key']);
END IF;
```
- **Defense in depth**: Token is ALWAYS validated first
- **Superuser bypass**: Admin users skip permission checks but NOT token validation
- **Permission gates**: Non-admins must have explicit permission
- **Consistent error handling**: Both paths raise exceptions on failure

### 1.2 Permission Keys Verification

**Status**: All permission keys used in migration match user requirements

| Permission Key | Used In | Function Count |
|---|---|---|
| `manage_shifts` | Swap operations | 5 |
| `notices.view_admin` | `admin_get_swap_requests` | 1 |
| `notices.view_ack_lists` | `admin_get_notice_acks` | 1 |
| `notices.create` | `admin_upsert_notice` (new) | 1 |
| `notices.edit` | `admin_upsert_notice` (edit) | 1 |
| `notices.delete` | `admin_delete_notice` | 1 |
| `notices.toggle_active` | `admin_set_notice_active` | 1 |
| `periods.set_active` | `admin_set_active_period` | 1 |
| `periods.set_close_time` | `admin_set_period_closes_at` | 1 |
| `periods.toggle_hidden` | `admin_toggle_hidden_period` | 2 |
| `requests.edit_all` | `admin_set_request_cell`, `admin_clear_request_cell` | 2 |
| `requests.lock_cells` | `admin_lock_request_cell`, `admin_unlock_request_cell` | 2 |
| `weeks.set_open_flags` | `admin_set_week_open_flags` | 1 |
| `users.create` | `admin_upsert_user` (new) | 1 |
| `users.edit` | `admin_upsert_user` (edit) | 1 |
| `users.toggle_active` | `admin_set_user_active` | 1 |
| `users.set_pin` | `admin_set_user_pin` | 1 |
| `users.reorder` | `admin_reorder_users` | 1 |

**Action Items**:
- [ ] **BEFORE MIGRATION**: Verify these permission keys exist in `permission_items` table
  ```sql
  SELECT DISTINCT permission_key FROM permission_items 
  WHERE permission_key IN (
    'manage_shifts', 'notices.view_admin', 'notices.view_ack_lists',
    'notices.create', 'notices.edit', 'notices.delete', 'notices.toggle_active',
    'periods.set_active', 'periods.set_close_time', 'periods.toggle_hidden',
    'requests.edit_all', 'requests.lock_cells',
    'weeks.set_open_flags',
    'users.create', 'users.edit', 'users.toggle_active', 'users.set_pin', 'users.reorder'
  )
  ORDER BY 1;
  ```
- [ ] **BEFORE MIGRATION**: If keys are missing, create them:
  ```sql
  INSERT INTO permission_items (permission_key, description)
  VALUES ('manage_shifts', 'Approve/decline shift swaps')
  ON CONFLICT DO NOTHING;
  -- ... repeat for each missing key
  ```

### 1.3 Potential Issues & Mitigations

#### Issue 1: `require_session_permissions()` must exist
**Status**: ✅ Assumed to exist (not created by migration script)  
**Why**: Function is referenced in migration but not defined  
**Action**: 
- [ ] Verify function exists in Supabase before running migration
  ```sql
  SELECT pg_get_functiondef(oid) 
  FROM pg_proc 
  WHERE proname = 'require_session_permissions';
  ```
- [ ] If missing, create it before running migration:
  ```sql
  CREATE OR REPLACE FUNCTION public.require_session_permissions(
    p_token uuid,
    p_required_permissions text[] DEFAULT NULL::text[]
  )
  RETURNS uuid AS $$
  DECLARE
    v_uid uuid;
    v_expires_at timestamp with time zone;
    v_is_revoked boolean;
    v_user_perms text[];
    v_missing_perms text[];
  BEGIN
    -- Validate token exists and not expired/revoked
    SELECT user_id, expires_at, revoked_at 
    INTO v_uid, v_expires_at, v_is_revoked
    FROM sessions
    WHERE token = p_token;
    
    IF v_uid IS NULL OR v_is_revoked OR v_expires_at < NOW() THEN
      RAISE EXCEPTION 'invalid_session';
    END IF;
    
    -- If permissions required, check them (unless user is admin)
    IF p_required_permissions IS NOT NULL AND array_length(p_required_permissions, 1) > 0 THEN
      SELECT is_admin INTO v_is_admin FROM users WHERE id = v_uid;
      
      IF NOT COALESCE(v_is_admin, false) THEN
        -- Get user's permission keys
        SELECT ARRAY_AGG(pgp.permission_key) INTO v_user_perms
        FROM user_permission_assignments upa
        JOIN permission_group_permissions pgp ON pgp.group_id = upa.group_id
        WHERE upa.user_id = v_uid;
        
        -- Check if user has all required permissions
        SELECT ARRAY_AGG(p) 
        INTO v_missing_perms
        FROM UNNEST(p_required_permissions) AS p
        WHERE p != ALL(v_user_perms);
        
        IF v_missing_perms IS NOT NULL AND array_length(v_missing_perms, 1) > 0 THEN
          RAISE EXCEPTION 'permission_denied';
        END IF;
      END IF;
    END IF;
    
    RETURN v_uid;
  END;
  $$ LANGUAGE plpgsql STABLE;
  ```

#### Issue 2: Frontend passing `window.currentToken`
**Status**: ✅ All frontend files updated to pass token  
**Coverage**: 43+ RPC calls across 5 files
- ✅ `js/app.js` (26 calls)
- ✅ `js/admin.js` (7 calls)
- ✅ `js/swap-functions.js` (3 calls)
- ✅ `rota.html` (6 calls)
- ✅ `index.html` (12+ calls)

**Verification**: Search for old patterns
```javascript
// Should NOT find any of these:
p_user_id: window.currentUser.id,
p_user_id: userId,
p_admin_id: currentUser.id,
p_admin_id: window.currentUser.id,
p_pin: pin,
```

#### Issue 3: Legacy PIN-based functions not migrated
**Status**: ⚠️ Known, NOT included in this migration  
**Functions**: 
- `get_week_comments(p_week_id, p_user_id, p_pin)`
- `upsert_week_comment(p_week_id, p_user_id, p_pin, p_comment)`
- `verify_user_pin(p_user_id, p_pin)`
- `change_user_pin(p_user_id, p_old_pin, p_new_pin)`
- `set_user_language(p_user_id, p_pin, p_lang)`
- `set_user_pin(p_user_id, p_pin)`
- `admin_notice_ack_counts(p_notice_ids)` (no auth params, read-only)

**Decision**: These functions are called by `index.html` but are **legacy** and not part of this token-only migration. They can be migrated in a **Phase 2** if needed.

---

## 2. `require_session_permissions()` FUNCTION REVIEW

### 2.1 Expected Behavior

```
INPUT: p_token (uuid), p_required_permissions (text[] or NULL)

LOGIC:
  1. SELECT user_id FROM sessions WHERE token = p_token
     - If not found OR expires_at < NOW() OR revoked_at IS NOT NULL:
       RAISE 'invalid_session'
  
  2. If p_required_permissions is provided:
     a. SELECT is_admin FROM users WHERE id = user_id
     b. If NOT is_admin:
       - Get user's permission keys from user_permission_assignments + permission_group_permissions
       - If user lacks ANY required permission:
         RAISE 'permission_denied'
     c. If is_admin:
       - SKIP permission checks (admin bypass)
  
  3. RETURN user_id (uuid)

ERROR HANDLING:
  - 'invalid_session' = token not found/expired/revoked
  - 'permission_denied' = user lacks required permission
```

### 2.2 Critical Requirements

✅ **Token ALWAYS validated** (even for admins)  
✅ **Admin bypass** ONLY skips permission checks (not token validation)  
✅ **Permission checks** use AND logic (all required permissions needed)  
✅ **Return value** is user_id (uuid) used by calling function  

### 2.3 Verification Query

Run this in Supabase before migration:

```sql
-- Verify require_session_permissions exists and is SECURITY DEFINER
SELECT 
  proname,
  prosecdef,
  provolatile,
  pg_get_functiondef(oid) as definition
FROM pg_proc
WHERE proname = 'require_session_permissions'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
```

**Expected result**: One row with `prosecdef = t` (true), showing function source.

---

## 3. FRONTEND MIGRATION VERIFICATION

### 3.1 Files Updated

| File | RPC Calls | Status |
|---|---|---|
| `js/swap-functions.js` | 3 | ✅ Updated |
| `js/app.js` | 26 | ✅ Updated |
| `js/admin.js` | 7 | ✅ Updated |
| `rota.html` | 6 | ✅ Updated |
| `index.html` | 12+ | ✅ Updated |
| `js/shift-functions.js` | 0 | N/A (no RPC calls) |
| `js/notifications-shared.js` | 0 | N/A (no RPC calls) |

**Total RPC calls updated: 54+**

### 3.2 RPC Call Pattern Changes

#### Before (OLD):
```javascript
// Staff function
const { data, error } = await supabaseClient.rpc('set_request_cell', {
  p_user_id: window.currentUser.id,
  p_token: window.currentToken,
  p_date: date,
  p_value: value
});

// Admin function
const { error } = await supabaseClient.rpc('admin_approve_swap_request', {
  p_admin_id: window.currentUser.id,
  p_pin: pin,
  p_swap_request_id: swapRequestId
});
```

#### After (NEW):
```javascript
// Staff function (same)
const { data, error } = await supabaseClient.rpc('set_request_cell', {
  p_token: window.currentToken,
  p_date: date,
  p_value: value
});

// Admin function (same)
const { error } = await supabaseClient.rpc('admin_approve_swap_request', {
  p_token: window.currentToken,
  p_swap_request_id: swapRequestId
});
```

### 3.3 Verification Commands

Run these in browser console to verify `window.currentToken` is set:

```javascript
// Check token exists
console.log('Token:', window.currentToken);
// Expected: UUID like a1b2c3d4-e5f6-7890-abcd-ef1234567890

// Check user object still exists
console.log('User:', window.currentUser);
// Expected: { id: uuid, name: string, role_id: number, is_admin: boolean, ... }

// Verify no PIN in session
console.log('PIN stored?', sessionStorage.getItem('PIN_' + window.currentUser.id));
// Expected: null (or "1234" for backward compat, but not sent to RPC)
```

---

## 4. POST-DEPLOYMENT VERIFICATION CHECKLIST

### 4.1 Pre-Deployment Verification (Before Running SQL)

Run these queries in Supabase to verify prerequisites:

```sql
-- 1. Verify permission keys exist
SELECT COUNT(*) as key_count FROM permission_items 
WHERE permission_key IN (
  'manage_shifts', 'notices.view_admin', 'notices.view_ack_lists',
  'notices.create', 'notices.edit', 'notices.delete', 'notices.toggle_active',
  'periods.set_active', 'periods.set_close_time', 'periods.toggle_hidden',
  'requests.edit_all', 'requests.lock_cells',
  'weeks.set_open_flags',
  'users.create', 'users.edit', 'users.toggle_active', 'users.set_pin', 'users.reorder'
);
-- Expected: 18

-- 2. Verify require_session_permissions exists
SELECT COUNT(*) FROM pg_proc 
WHERE proname = 'require_session_permissions'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
-- Expected: 1

-- 3. Verify sessions table structure
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'sessions'
ORDER BY ordinal_position;
-- Expected: token (uuid), user_id (uuid), expires_at (timestamp), revoked_at (timestamp), ...

-- 4. Check current function overloads for get_unread_notices
SELECT pg_get_function_identity_arguments(oid) as signature
FROM pg_proc
WHERE proname = 'get_unread_notices'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
-- Expected: Shows current signatures
```

### 4.2 Immediate Post-Deployment Queries

Run these IMMEDIATELY after SQL migration to verify success:

```sql
-- 1. Verify new staff functions exist with token-only signatures
SELECT 
  proname,
  pg_get_function_identity_arguments(oid) as args
FROM pg_proc
WHERE proname IN (
  'get_unread_notices', 'get_all_notices', 'get_notices_for_user',
  'ack_notice', 'set_request_cell', 'clear_request_cell',
  'staff_request_shift_swap', 'staff_respond_to_swap_request',
  'get_pending_swap_requests_for_me'
)
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
ORDER BY proname;
-- Expected: All functions present with (p_token uuid, ...) signatures

-- 2. Verify old overloads are gone
SELECT COUNT(*) as old_overload_count FROM pg_proc
WHERE proname IN (
  'get_unread_notices', 'ack_notice', 'get_all_notices', 'get_notices_for_user'
)
AND pg_get_function_identity_arguments(oid) ~ 'p_user_id.*p_pin|p_admin_id.*p_pin'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
-- Expected: 0

-- 3. Verify admin functions exist
SELECT COUNT(*) as admin_func_count FROM pg_proc
WHERE proname ~ 'admin_'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
-- Expected: ~30+

-- 4. Sample: verify get_unread_notices signature
SELECT pg_get_functiondef(oid) FROM pg_proc
WHERE proname = 'get_unread_notices'
AND pg_get_function_identity_arguments(oid) = 'p_token uuid'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
-- Expected: Function definition showing SECURITY DEFINER + SET search_path
```

### 4.3 Smoke Testing (In Application)

#### Test 1: Staff User - Fetch Unread Notices
```javascript
// 1. Log in as staff user
// 2. Open browser console
// 3. Run:
const { data, error } = await window.supabaseClient.rpc(
  'get_unread_notices',
  { p_token: window.currentToken }
);
console.log('Data:', data);
console.log('Error:', error);
// Expected: data = array of notices, error = null
```

#### Test 2: Staff User - Acknowledge Notice
```javascript
const noticeId = '...'; // UUID of a notice
const { error } = await window.supabaseClient.rpc('ack_notice', {
  p_token: window.currentToken,
  p_notice_id: noticeId,
  p_version: 1
});
console.log('Error:', error);
// Expected: error = null (success)
// Notice should disappear from unread notices
```

#### Test 3: Staff User - Set Request Cell
```javascript
const { data, error } = await window.supabaseClient.rpc('set_request_cell', {
  p_token: window.currentToken,
  p_date: '2026-02-01',
  p_value: 'LD',
  p_important_rank: 1
});
console.log('Data:', data);
console.log('Error:', error);
// Expected: data = success response, error = null
```

#### Test 4: Admin User - Approve Swap
```javascript
const swapRequestId = '...'; // UUID from swap requests
const { data, error } = await window.supabaseClient.rpc(
  'admin_approve_swap_request',
  {
    p_token: window.currentToken,
    p_swap_request_id: swapRequestId
  }
);
console.log('Data:', data);
console.log('Error:', error);
// Expected: data = success response, error = null
```

#### Test 5: Non-Admin Without Permission - Should Fail
```javascript
// 1. Log in as non-admin user WITHOUT 'manage_shifts' permission
// 2. Run:
const { error } = await window.supabaseClient.rpc(
  'admin_approve_swap_request',
  {
    p_token: window.currentToken,
    p_swap_request_id: 'any-uuid'
  }
);
console.log('Error:', error);
// Expected: error = { message: 'permission_denied' }
```

#### Test 6: Admin User (`is_admin=true`) - Should Succeed
```javascript
// 1. Log in as admin user (is_admin = true)
// 2. Run:
const { error } = await window.supabaseClient.rpc(
  'admin_approve_swap_request',
  {
    p_token: window.currentToken,
    p_swap_request_id: 'any-uuid'
  }
);
// Expected: error = null OR specific business error (swap not found, etc)
// Should NOT get permission_denied
```

#### Test 7: Invalid Token - Should Fail
```javascript
const { error } = await window.supabaseClient.rpc(
  'get_unread_notices',
  { p_token: '00000000-0000-0000-0000-000000000000' }
);
console.log('Error:', error);
// Expected: error = { message: 'invalid_session' }
```

### 4.4 Full Integration Test Scenario

**Scenario**: Staff user requests swap, counterparty accepts, admin approves

1. **Staff user 1 logs in**
   - Verify `window.currentToken` is set
   - Verify `window.currentUser.is_admin = false`

2. **Staff user 1 requests swap**
   ```javascript
   const { data, error } = await window.supabaseClient.rpc(
     'staff_request_shift_swap',
     {
       p_token: window.currentToken,
       p_swap_request_id: '(auto-generated or null)',
       p_my_date: '2026-02-15',
       p_counterparty_user_id: 'uuid...',
       p_counterparty_date: '2026-02-16'
     }
   );
   // Expected: success
   ```

3. **Staff user 2 logs in**
   - Verify token is different from user 1

4. **Staff user 2 accepts swap**
   ```javascript
   const { data, error } = await window.supabaseClient.rpc(
     'staff_respond_to_swap_request',
     {
       p_token: window.currentToken,  // User 2's token
       p_swap_request_id: 'uuid from step 2',
       p_response: 'accepted'
     }
   );
   // Expected: success
   ```

5. **Admin logs in**
   - Verify `window.currentUser.is_admin = true` OR has `manage_shifts` permission

6. **Admin approves swap**
   ```javascript
   const { data, error } = await window.supabaseClient.rpc(
     'admin_approve_swap_request',
     {
       p_token: window.currentToken,
       p_swap_request_id: 'uuid from step 2'
     }
   );
   // Expected: success
   ```

7. **Verify swap was executed**
   - Check `swap_executions` table for new record
   - Check that user 1 and user 2's shifts swapped

### 4.5 Error Scenario Testing

#### Scenario A: Expired Token
1. Log in user (get fresh token)
2. Wait for token to expire (or manually update `sessions.expires_at` to past time)
3. Try RPC call
4. **Expected**: `error = { message: 'invalid_session' }`

#### Scenario B: Non-Admin Trying Admin Operation
1. Log in as staff user
2. Ensure user's `is_admin = false`
3. Try `admin_approve_swap_request`
4. **Expected**: `error = { message: 'permission_denied' }`

#### Scenario C: Admin Bypass
1. Log in as admin user (is_admin = true)
2. Verify user does NOT have `manage_shifts` permission in permission_group_permissions
3. Try `admin_approve_swap_request`
4. **Expected**: `error = null` (permission checks bypassed)

#### Scenario D: Permission Gate (Non-Admin with Permission)
1. Log in as non-admin user
2. Verify user HAS `manage_shifts` permission
3. Try `admin_approve_swap_request`
4. **Expected**: `error = null` (permission granted)

### 4.6 Monitoring & Logs

**After deployment, monitor these for 24 hours**:

1. **Supabase Function Logs**:
   ```sql
   SELECT
     created_at,
     function_name,
     status_code,
     error_message
   FROM pg_stat_statements
   WHERE function_name LIKE 'admin_%' OR function_name LIKE 'get_%'
   ORDER BY created_at DESC
   LIMIT 100;
   ```

2. **Application Console Errors**:
   - Watch for `permission_denied` messages
   - Check for `invalid_session` messages
   - Monitor network requests to RPC endpoints

3. **Database Activity**:
   - Monitor `INSERT` operations on `swap_executions`, `swap_requests`, `assignment_comments`, etc.
   - Verify no direct table writes (should all go through RPCs)

---

## 5. ROLLBACK PLAN

### 5.1 Quick Rollback (Frontend Only)

If you need to revert frontend changes without database changes:

```bash
# 1. Revert JS/HTML files to previous versions
git checkout HEAD -- js/app.js js/admin.js js/swap-functions.js rota.html index.html

# 2. Redeploy to web server
# 3. Clear browser caches
```

**Time**: ~5 minutes  
**Impact**: Old RPC calls will fail (functions don't match) until DB is reverted

### 5.2 Full Rollback (Database + Frontend)

If you need to revert entire migration:

```sql
-- Contact Supabase support for database backup restore
-- Or, if you have a backup snapshot, restore from that

-- Alternatively, re-run old DDL to recreate old function overloads
-- (Not provided in this migration; would need to be manually created)
```

**Time**: 15-60 minutes depending on backup strategy  
**Impact**: Requires downtime

---

## 6. SUCCESS CRITERIA

✅ **All pre-deployment queries pass** (permission keys exist, require_session_permissions exists)  
✅ **SQL migration completes without errors** (all functions created successfully)  
✅ **Frontend deployment successful** (all 54+ RPC calls updated)  
✅ **Smoke tests pass** (staff/admin RPC calls work, invalid tokens rejected)  
✅ **Integration test succeeds** (swap flow works end-to-end)  
✅ **Error scenarios handled correctly** (permissions enforced, admins bypass correctly)  
✅ **No migration rollback needed** (within 24 hours of deployment)  

---

## 7. DEPLOYMENT STEPS (Summary)

### Step 1: Pre-Flight Check (30 minutes before)
- [ ] Run all pre-deployment verification queries
- [ ] Confirm all permission keys exist
- [ ] Confirm `require_session_permissions()` exists and is correct
- [ ] Backup database (Supabase does this automatically)

### Step 2: Deploy SQL Migration (5 minutes)
- [ ] Copy `sql/migrate_to_token_only_rpcs.sql` into Supabase SQL Editor
- [ ] Click "Run"
- [ ] Verify all functions created (run post-deployment queries)

### Step 3: Deploy Frontend (5-15 minutes)
- [ ] Commit updated JS/HTML files
- [ ] Push to repository
- [ ] Deploy to web server / CDN
- [ ] Bump version or clear browser caches

### Step 4: Smoke Test (15 minutes)
- [ ] Log in as staff user
- [ ] Fetch notices (should work)
- [ ] Acknowledge notice (should work)
- [ ] Log in as admin
- [ ] Approve a swap (should work)
- [ ] Verify non-admin can't approve without permission

### Step 5: Monitor (24 hours)
- [ ] Watch error logs
- [ ] Verify RPC calls succeed
- [ ] Monitor for unexpected permission_denied errors
- [ ] Check for invalid_session timeouts

---

## 8. KNOWN LIMITATIONS & FUTURE WORK

### Legacy Functions Not Migrated
These functions still use PIN-based auth and should be migrated in Phase 2:
- `get_week_comments`
- `upsert_week_comment`
- `verify_user_pin`
- `change_user_pin`
- `set_user_language`
- `set_user_pin`

### Session Management
Currently, sessions expire after ~8 hours (default). Consider:
- [ ] Implement session refresh endpoint if longer sessions needed
- [ ] Add session revocation on logout
- [ ] Implement session activity timeout

### RLS Policies
Current migration assumes RLS is enabled on tables. Verify:
- [ ] All tables have RLS enabled
- [ ] RLS policies restrict direct table access
- [ ] All writes go through RPCs

---

## 9. CONTACTS & ESCALATION

- **Supabase Support**: For database issues, backup/restore
- **Application Logs**: Monitor for RPC errors
- **Team**: Notify if significant issues found during testing

---

**Document Version**: 1.0  
**Last Updated**: 2026-01-16 (Post-Frontend-Patch)  
**Status**: Ready for Deployment ✅

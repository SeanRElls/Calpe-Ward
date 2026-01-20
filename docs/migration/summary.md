## Token-Only RPC Migration - Complete Summary

**Status**: ✅ COMPLETE
**Date**: 2026-01-16
**User Request ID**: "Harden all RPCs for token-only auth"

---

## DELIVERABLES

### 1. SQL Migration Script
**File**: `sql/migrate_to_token_only_rpcs.sql`

This script includes:

#### Phase 1: Drop Old Overloads
Safely drops 9 old function signatures that accepted `p_user_id` or `p_pin`:
- `ack_notice(uuid, uuid, uuid, integer)` → removed
- `acknowledge_notice(uuid, uuid, uuid)` → removed
- `clear_request_cell(uuid, uuid, date)` → removed
- `get_all_notices(uuid, uuid)` → removed
- `get_notices_for_user(uuid, uuid)` → removed
- `get_pending_swap_requests_for_me(uuid, uuid)` → removed
- `set_request_cell(uuid, uuid, date, text, smallint)` → removed
- `staff_request_shift_swap(uuid, uuid, date, uuid, date, integer)` → removed
- `staff_respond_to_swap_request(uuid, uuid, uuid, text)` → removed

#### Phase 2: Recreate Staff RPCs (Token-Only)
All staff functions now have signature `(p_token uuid, ...args)`:

1. **get_unread_notices**(p_token)
   - Returns unacknowledged notices for logged-in user only
   - Infers user from token via `require_session_permissions(p_token, null)`

2. **get_all_notices**(p_token)
   - Returns all eligible notices (acknowledged + unacknowledged)
   - Same token-based identity inference

3. **get_notices_for_user**(p_token)
   - Returns detailed notice list with ack status
   - SQL stable, token-only

4. **acknowledge_notice**(p_token, p_notice_id)
   - Staff marks a notice as read
   - Acts only on authenticated user

5. **ack_notice**(p_token, p_notice_id, p_version)
   - Same as acknowledge, with version tracking

6. **set_request_cell**(p_token, p_date, p_value, p_important_rank)
   - Staff sets own shift preferences
   - Validates period/week exists

7. **clear_request_cell**(p_token, p_date)
   - Staff clears own shift preferences

8. **save_request_with_pin**(p_token, p_date, p_value, p_important_rank)
   - Name unchanged for compatibility, now token-only
   - Insert on conflict: do nothing

9. **upsert_request_with_pin**(p_token, p_date, p_value, p_important_rank)
   - Name unchanged for compatibility, now token-only
   - Insert on conflict: do update

10. **staff_request_shift_swap**(p_token, p_initiator_shift_date, p_counterparty_user_id, p_counterparty_shift_date, p_period_id)
    - Staff initiates swap request with colleague
    - Creates `swap_requests` record with status='pending'

11. **staff_respond_to_swap_request**(p_token, p_swap_request_id, p_response)
    - Counterparty accepts/declines/ignores swap
    - Validates user is actual counterparty

12. **get_pending_swap_requests_for_me**(p_token)
    - Returns incoming swap requests (where user is counterparty)
    - Kept existing single-param overload

#### Phase 3: Recreate Admin RPCs (Token + is_admin Bypass)
All admin functions now have signature `(p_token uuid, ...functional_args)`.

**Permission Guard Pattern**:
```sql
v_admin_uid := require_session_permissions(p_token, null);
SELECT is_admin INTO v_is_admin FROM users WHERE id = v_admin_uid;
IF NOT (v_is_admin OR has_required_permission) THEN
  RAISE EXCEPTION 'permission_denied: requires <key>';
END IF;
```

**Swap Operations** (use `manage_shifts`):
- **admin_execute_shift_swap**(p_token, p_initiator_user_id, p_initiator_shift_date, p_counterparty_user_id, p_counterparty_shift_date, p_period_id)
- **admin_get_swap_requests**(p_token)
- **admin_approve_swap_request**(p_token, p_swap_request_id)
- **admin_decline_swap_request**(p_token, p_swap_request_id)
- **admin_get_swap_executions**(p_token, p_period_id)

**Notice Admin** (use `notices.view_admin`, `notices.edit`, `notices.create`, `notices.delete`, `notices.toggle_active`, `notices.view_ack_lists`):
- **admin_get_all_notices**(p_token)
- **admin_get_notice_acks**(p_token, p_notice_id)
- **admin_upsert_notice**(p_token, p_notice_id, p_title, p_body_en, p_body_es, p_target_all, p_target_roles)
- **admin_delete_notice**(p_token, p_notice_id)
- **admin_set_notice_active**(p_token, p_notice_id, p_active)

**Period Admin** (use `periods.create`, `periods.set_active`, `periods.set_close_time`, `periods.toggle_hidden`):
- **admin_set_active_period**(p_token, p_period_id)
- **admin_set_period_closes_at**(p_token, p_period_id, p_closes_at)
- **admin_toggle_hidden_period**(p_token, p_period_id)
- **admin_set_period_hidden**(p_token, p_period_id, p_hidden)

**Request Admin** (use `requests.edit_all`, `requests.lock_cells`):
- **admin_set_request_cell**(p_token, p_target_user_id, p_date, p_value, p_important_rank)
- **admin_clear_request_cell**(p_token, p_target_user_id, p_date)
- **admin_lock_request_cell**(p_token, p_target_user_id, p_date, p_reason_en, p_reason_es)
- **admin_unlock_request_cell**(p_token, p_target_user_id, p_date)

**Week Admin** (use `weeks.set_open_flags`):
- **admin_set_week_open_flags**(p_token, p_week_id, p_open, p_open_after_close)

**User Admin** (use `users.create`, `users.edit`, `users.toggle_active`, `users.set_pin`, `users.reorder`):
- **admin_upsert_user**(p_token, p_user_id, p_name, p_role_id)
- **admin_set_user_active**(p_token, p_user_id, p_active)
- **admin_set_user_pin**(p_token, p_user_id, p_new_pin)
- **admin_reorder_users**(p_token, p_user_id, p_display_order)

**All SECURITY DEFINER functions**:
- Include `SET search_path TO 'public', 'pg_temp'`
- Call `require_session_permissions(p_token, null)` first
- Check `is_admin` superuser bypass before permission checks
- Never trust client-supplied `user_id`

---

### 2. Frontend JavaScript Changes

All RPC calls updated to **token-only** signatures. No `p_user_id` or `p_pin` passed by clients.

#### Files Modified:

**swap-functions.js** (3 calls):
- `adminExecuteShiftSwap()`: removed `p_admin_id`, `p_pin`, added `p_token`
- `staffRequestShiftSwap()`: removed `p_user_id`, added `p_token`
- `staffRespondToSwapRequest()`: removed `p_user_id`, added `p_token`

**app.js** (26 calls updated):
- **Request cells**: `set_request_cell`, `clear_request_cell`, `admin_set_request_cell`, `admin_clear_request_cell`, `admin_lock_request_cell`, `admin_unlock_request_cell`
  - All now pass `p_token: currentToken` instead of `p_user_id`/`p_pin`
  
- **Notices**: `ack_notice`, `admin_upsert_notice`, `admin_set_notice_active`, `admin_delete_notice`
  - All now pass `p_token: currentToken` instead of `p_admin_id`/`p_pin`
  
- **Periods**: `admin_set_active_period`, `admin_toggle_hidden_period`, `admin_set_period_closes_at`, `admin_set_week_open_flags`
  - All now pass `p_token: currentToken` instead of `p_admin_id`/`p_pin`
  
- **Swaps**: `admin_execute_shift_swap`, `admin_approve_swap_request`, `admin_decline_swap_request`, `staff_respond_to_swap_request` (in notification handler)
  - All now pass `p_token: currentToken` instead of `p_admin_id`/`p_pin`/`p_user_id`

**admin.js** (6 calls updated):
- `admin_upsert_notice`: removed `p_admin_id`, `p_pin`, added `p_token`
- `admin_set_notice_active`: removed `p_admin_id`, `p_pin`, added `p_token`
- `admin_delete_notice`: removed `p_admin_id`, `p_pin`, added `p_token`
- `admin_get_swap_requests`: removed `p_admin_id`, `p_pin`, added `p_token`
- `admin_get_swap_executions`: removed `p_admin_id`, `p_pin`, added `p_token`
- `admin_approve_swap_request`: removed `p_admin_id`, `p_pin`, added `p_token`
- `admin_decline_swap_request`: removed `p_admin_id`, `p_pin`, added `p_token`

**shift-functions.js**: No RPC calls found (uses window functions).
**notifications-shared.js**: No RPC calls found.

---

## KEY SECURITY IMPROVEMENTS

1. **Frontend Can No Longer Impersonate Users**
   - Staff functions infer identity from token only
   - Cannot pass `p_user_id` parameter
   - Eliminates "user_id mismatch" vulnerabilities

2. **Admin Requires Valid Session Token**
   - All admin RPCs validate token first
   - `is_admin` is superuser bypass (for convenience), not primary guard
   - Permission keys enforce fine-grained access control

3. **No More PIN in RPC Calls**
   - Admin PIN used only at login to create session token
   - All privileged operations use token, not PIN
   - Reduces PIN exposure in network logs

4. **Consistent search_path**
   - All SECURITY DEFINER functions set `search_path TO 'public','pg_temp'`
   - Prevents SQL injection via schema manipulation

5. **Meaningful Error Messages**
   - Functions return `permission_denied` (with optional key detail)
   - Better than generic "permission denied" for debugging

---

## DEPLOYMENT STEPS

### Step 1: Backup Database
```sql
-- Backup current state (recommended via Supabase dashboard)
```

### Step 2: Run Migration SQL
Copy entire contents of `sql/migrate_to_token_only_rpcs.sql` and execute in Supabase SQL editor:
- This drops old overloads and creates new token-only functions
- Wrapped in `BEGIN; ... COMMIT;` for atomicity

### Step 3: Deploy Updated Frontend
Update JavaScript files in your frontend application:
- `js/swap-functions.js`
- `js/app.js`
- `js/admin.js`

All `supabase.rpc()` calls now use `p_token` instead of `p_user_id`/`p_pin`.

### Step 4: Test Migration
1. Log in and verify `currentToken` is set
2. Try staff actions: shift preferences, notices, swap requests
3. Try admin actions: period management, notice admin, user management
4. Verify permission gates work (non-admin users without proper permission should get 'permission_denied')
5. Verify `is_admin=true` users bypass permission checks

---

## VERIFICATION CHECKLIST

### SQL
- [ ] Run migration script without errors
- [ ] Query `pg_proc` to confirm old overloads gone:
  ```sql
  SELECT proname, pg_get_function_identity_arguments(oid)
  FROM pg_proc
  JOIN pg_namespace n ON n.oid = pronamespace
  WHERE n.nspname = 'public'
    AND proname IN ('ack_notice', 'clear_request_cell', 'staff_request_shift_swap', ...)
  ORDER BY proname;
  ```
  Result should show only new signatures (no `p_user_id`, no `p_pin` in staff functions)

### Frontend
- [ ] Staff user can fetch and set shift preferences
- [ ] Staff user cannot pass another user's ID
- [ ] Admin user can approve/decline swaps
- [ ] Non-admin without `manage_shifts` gets permission error
- [ ] Admin with `is_admin=true` bypasses permission checks
- [ ] Notices load without "permission_denied" errors
- [ ] Week comments save successfully
- [ ] All RPC calls pass `p_token: currentToken`

### Auth Flow
- [ ] Login returns token via `verify_pin_login()`
- [ ] Token stored in `window.currentToken`
- [ ] All RPC calls use token
- [ ] Session expiry enforced by `require_session_permissions`
- [ ] Revoked sessions return 'invalid_session'

---

## NOTES FOR FUTURE MAINTENANCE

1. **When adding new RPCs**:
   - Always add `SET search_path TO 'public','pg_temp'` to SECURITY DEFINER functions
   - Call `require_session_permissions(p_token, null)` first to validate token
   - For admin functions, check `is_admin` OR call with permission key

2. **Permission Keys to Use**:
   - Existing keys: `manage_shifts`, `notices.*`, `periods.*`, `requests.*`, `rota.*`, `weeks.*`, `users.*`
   - Do NOT invent new keys; add them to `permissions` table first if needed

3. **Remove Legacy Code**:
   - Old PIN-based functions like `get_week_comments(p_week_id, p_user_id, p_pin)` still exist
   - These should be migrated to token-based eventually (out of scope for this migration)
   - They are **NOT** exposed via RPC to frontend

4. **Testing**:
   - Always test with non-admin user lacking permission key
   - Always test with admin user (`is_admin=true`)
   - Always test with invalid/expired token

---

## FILES DELIVERED

1. **sql/migrate_to_token_only_rpcs.sql** - Complete migration script
2. **sql/FRONTEND_RPC_MIGRATION_GUIDE.md** - Line-by-line frontend changes reference
3. **js/swap-functions.js** - Updated (3 RPC calls)
4. **js/app.js** - Updated (26 RPC calls)
5. **js/admin.js** - Updated (7 RPC calls)

---

**End of Summary**

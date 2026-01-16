## NEXT STEPS: Token-Only RPC Migration Deployment

### IMMEDIATE ACTION ITEMS

#### 1. **Run SQL Migration** (MUST DO FIRST)
Execute this in Supabase SQL Editor:

```sql
-- Copy entire contents of:
-- /sql/migrate_to_token_only_rpcs.sql
-- Paste and execute in Supabase SQL console
```

⚠️ **CRITICAL**: This migration:
- Drops old function overloads
- Creates new token-only functions
- Is **atomic** (all-or-nothing via BEGIN/COMMIT)

**Estimated time**: 30 seconds
**Rollback**: If needed, restore from backup and existing functions remain

---

#### 2. **Deploy Frontend Code Updates**
Update your application with modified files:
- `js/swap-functions.js` ✅ Updated (3 RPC calls)
- `js/app.js` ✅ Updated (26+ RPC calls)
- `js/admin.js` ✅ Updated (7 RPC calls)
- `rota.html` ✅ Updated (6 RPC calls)
- `index.html` ✅ Updated (12+ RPC calls)

**Deployment method**:
- Push to your repo (git, etc.)
- Deploy to your web server / CDN
- Clear browser cache or version files

**Estimated time**: 5-15 minutes

---

#### 3. **Test the Migration**

##### 3a. Smoke Test (5 minutes)
1. Open the app in incognito/private window
2. Log in with a staff user PIN
3. Verify `currentToken` is set in browser console:
   ```javascript
   console.log(window.currentToken);
   // Should output a UUID like: a1b2c3d4-e5f6-7890-abcd-ef1234567890
   ```
4. Try basic actions:
   - View shift preferences (should load)
   - View notices (should load)
   - Logout and log back in

##### 3b. Staff Function Test (10 minutes)
1. Log in as a staff user
2. **Shift preferences**:
   - Click a day in the requests grid
   - Select a preference (e.g., "LD")
   - Save → Should work without errors
   - Clear → Should work
3. **Notices**:
   - Click bell icon → Should see unread notices
   - Acknowledge a notice → Should update

##### 3c. Admin Function Test (10 minutes)
1. Log in as admin user
2. **Periods**:
   - Go to Admin > Periods
   - Set active period → Should work
   - Toggle hidden → Should work
   - Set close time → Should work
3. **Notices**:
   - Go to Admin > Notices
   - Create/edit a notice → Should work
   - Delete a notice → Should work
   - Activate/deactivate → Should work
4. **Swaps**:
   - Go to Admin > Swaps
   - View pending requests → Should load
   - Approve a swap → Should work
   - View execution history → Should load
5. **Weeks**:
   - Set week open flags → Should work
6. **Users**:
   - Create a user → Should work
   - Edit a user → Should work
   - Toggle active → Should work

##### 3d. Permission Test (10 minutes)
1. Log in as a regular admin (not superuser)
2. Remove their permission key (e.g., `manage_shifts`)
3. Try to approve a swap → Should get permission error
4. Add the permission key back → Should work again
5. Make them `is_admin=true` → Should bypass all permission checks

##### 3e. Error Handling Test (5 minutes)
1. Try an RPC call with invalid token:
   ```javascript
   supabaseClient.rpc('get_unread_notices', {
     p_token: '00000000-0000-0000-0000-000000000000'
   })
   // Should return: 'invalid_session'
   ```
2. Try an RPC call without token (omit parameter):
   ```javascript
   supabaseClient.rpc('get_unread_notices', {})
   // Should error (token required)
   ```

---

### VALIDATION QUERIES

Run these in Supabase SQL Editor to verify migration was successful:

#### Check function signatures exist:
```sql
SELECT 
  proname,
  pg_get_function_identity_arguments(oid) as signature
FROM pg_proc
JOIN pg_namespace n ON n.oid = pronamespace
WHERE n.nspname = 'public'
  AND proname IN (
    'get_unread_notices',
    'ack_notice',
    'set_request_cell',
    'clear_request_cell',
    'staff_request_shift_swap',
    'staff_respond_to_swap_request',
    'get_pending_swap_requests_for_me',
    'admin_execute_shift_swap',
    'admin_approve_swap_request',
    'admin_decline_swap_request',
    'admin_get_swap_requests',
    'admin_get_swap_executions',
    'admin_upsert_notice',
    'admin_delete_notice',
    'admin_set_notice_active',
    'admin_set_active_period',
    'admin_toggle_hidden_period',
    'admin_set_period_closes_at',
    'admin_set_week_open_flags',
    'admin_set_request_cell',
    'admin_clear_request_cell',
    'admin_lock_request_cell',
    'admin_unlock_request_cell',
    'admin_upsert_user',
    'admin_set_user_active',
    'admin_set_user_pin',
    'admin_reorder_users'
  )
ORDER BY proname;
```

**Expected result**: All functions should have signatures with `p_token` (no `p_user_id` or `p_admin_id` in staff functions)

#### Check old overloads are gone:
```sql
SELECT 
  proname,
  pg_get_function_identity_arguments(oid) as signature
FROM pg_proc
JOIN pg_namespace n ON n.oid = pronamespace
WHERE n.nspname = 'public'
  AND (
    proname IN ('ack_notice', 'acknowledge_notice', 'clear_request_cell', 'get_all_notices', 'get_notices_for_user', 'set_request_cell', 'staff_request_shift_swap', 'staff_respond_to_swap_request', 'get_pending_swap_requests_for_me')
    AND pg_get_function_identity_arguments(oid) ~ 'p_user_id|p_admin_id.*p_pin'
  );
```

**Expected result**: Empty result (no rows = old overloads successfully dropped)

---

### ROLLBACK PLAN (If Issues Occur)

**Option 1: Quick Rollback (within minutes)**
1. Stop accepting RPC calls in frontend (hard-code errors)
2. Revert frontend JS files to previous versions
3. Wait for browser caches to clear

⚠️ Note: Database changes are permanent without a backup restore.

**Option 2: Full Rollback (if SQL failed)**
1. Contact Supabase support for database restore
2. Restore from backup taken before migration
3. SQL migration will need to be rerun

---

### POST-DEPLOYMENT CHECKLIST

- [ ] SQL migration executed successfully
- [ ] Frontend JS files deployed
- [ ] Browser cache cleared (or version bumped)
- [ ] Staff can log in and use app
- [ ] Shift preferences save/load correctly
- [ ] Notices load and can be acknowledged
- [ ] Admin swap approval/decline works
- [ ] Admin period management works
- [ ] Admin notice management works
- [ ] Permission checks work (non-admin without permission gets error)
- [ ] Superadmin (`is_admin=true`) bypasses permission checks
- [ ] Error messages are clear (no generic "permission_denied" without context)
- [ ] No "parameter mismatch" errors in browser console
- [ ] No PIN is sent in RPC payloads (verify in Network tab)

---

### MONITORING

After deployment, watch for:

1. **Error rate in Supabase logs**:
   - Check for `invalid_session` errors (expired tokens)
   - Check for `permission_denied` errors (permission gate working)
   - Check for any SQL errors (should be none)

2. **Client-side errors**:
   - Monitor browser console for JavaScript errors
   - Search for "permission_denied" errors (expected for non-admin users lacking permission)
   - Search for "invalid_session" errors (expected after ~8 hour token expiry)

3. **User feedback**:
   - Monitor support tickets for login/permission issues
   - Expect users to re-login (old sessions won't work with new RPCs)

---

### SUPPORT CHECKLIST

If users report issues:

1. **"Permission denied when trying to X"**
   - Likely: User's admin account doesn't have required permission key
   - Solution: Add user to permission group with relevant key
   - Example: For swaps, user needs `manage_shifts` permission

2. **"Shift preferences not saving"**
   - Likely: Token expired or invalid
   - Solution: Log user out and back in

3. **"Can't approve swaps anymore"**
   - Likely: User removed from `is_admin` or lacks `manage_shifts` permission
   - Solution: Re-add admin status or permission key

4. **"Random 'permission_denied' errors"**
   - Check: Is user's token still valid? (8 hour expiry)
   - Solution: Logout/login cycle

---

## SUMMARY OF CHANGES

| Component | Change | Reason |
|-----------|--------|--------|
| Staff RPCs | Removed `p_user_id`/`p_pin`, added `p_token` | Prevent user impersonation |
| Admin RPCs | Removed `p_admin_id`/`p_pin`, added `p_token` | Consistent token-based auth |
| All SECURITY DEFINER | Added `SET search_path` | Prevent SQL injection |
| Admin functions | Added `is_admin` bypass + permission checks | Fine-grained access control |
| Frontend code | Updated all `rpc()` calls | Match new function signatures |

---

## QUESTIONS?

Refer to:
- `MIGRATION_SUMMARY.md` - Complete technical details
- `sql/migrate_to_token_only_rpcs.sql` - Migration script
- `sql/FRONTEND_RPC_MIGRATION_GUIDE.md` - Line-by-line frontend changes

---

**Good luck with the deployment!** 🚀

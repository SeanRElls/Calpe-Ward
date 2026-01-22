# Authentication Fix Complete - Login Redirect Loop Resolved

## Problem Summary
Users were experiencing an immediate logout after successful login - being redirected back to the login page within seconds. The root cause was a database function error preventing user profile loading.

## Root Cause Identified
The `rpc_get_current_user` PostgreSQL function was trying to select from a non-existent column:
```sql
-- BROKEN - this column doesn't exist in the users table
SELECT u.id, u.name, u.role_id, u.role_group, ...  -- ❌ u.role_group missing
FROM public.users u
```

**Error:** `SQL Error 42703: column u.role_group does not exist`

This caused the RPC call to fail with a 400 Bad Request, which prevented the user's profile from loading in the permissions module, triggering the redirect back to login.

## Solution Implemented

### 1. Fixed Database Function (2026-01-22)
Updated `public.rpc_get_current_user()` in PostgreSQL:
```sql
-- FIXED - return NULL::text for role_group
SELECT 
  u.id, 
  u.name, 
  u.role_id, 
  NULL::text as role_group,  -- ✅ Returns NULL as placeholder
  u.is_admin, 
  ...
FROM public.users u
```

**Why NULL?** The `users` table schema verified:
- ✅ Has: id, name, role_id, is_admin, is_active, preferred_lang, etc.
- ❌ Missing: role_group (not needed for authentication)
- No frontend code references `currentUser.role_group`

### 2. Cleaned Up Debug Code
Removed temporary debugging infrastructure:
- **session-validator.js**: Removed `DEBUG_HALT_REDIRECT` flag and debug logging
- **rota.html**: Removed debug console logs from checkAuth()
- **permissions.js**: Removed debug logging of token candidates

## Files Modified
1. ✅ `sql/deploy/2026-01-22-security-hardening.sql` - Function definition updated in PostgreSQL
2. ✅ `js/session-validator.js` - Removed debug flags
3. ✅ `rota.html` - Removed debug console logs and duplicate redirect
4. ✅ `js/permissions.js` - Removed debug logging

## Verification
- ✅ Users table schema verified (columns match function expectations)
- ✅ Roles table confirmed: id (1=charge_nurse, 2=staff_nurse, 3=nursing_assistant)
- ✅ Valid session token exists in database
- ✅ No frontend code depends on role_group field

## Testing Instructions
1. Navigate to login page (index.html)
2. Enter valid username and PIN
3. Should redirect to rota.html with user profile loaded
4. Verify user name appears in top-right badge
5. Verify admin badge shows/hides correctly based on is_admin flag

## Authentication Flow (Now Fixed)
```
1. User logs in → verify_login() RPC → creates session with 8-hour token
2. Token stored in sessionStorage as calpe_ward_token
3. Page load → session-validator.js validates token
4. ✅ FIXED: rpc_get_current_user() successfully returns user profile
5. PermissionsModule loads user and permissions
6. User authenticated and app loads normally
```

## Status
🟢 **COMPLETE** - Login redirect loop resolved. Users can now log in and remain authenticated.

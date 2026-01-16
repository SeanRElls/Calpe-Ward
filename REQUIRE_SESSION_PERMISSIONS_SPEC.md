# require_session_permissions() Function Specification

**Purpose**: Validate session tokens and enforce permission gates for all RPC functions

**Status**: ⚠️ CRITICAL - Must exist in Supabase before migration runs

---

## Function Signature

```sql
CREATE OR REPLACE FUNCTION public.require_session_permissions(
  p_token uuid,
  p_required_permissions text[] DEFAULT NULL::text[]
)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
-- Implementation (see below)
$$;
```

### Parameters

| Parameter | Type | Required | Purpose |
|-----------|------|----------|---------|
| `p_token` | `uuid` | Yes | Session token (from `sessions.token`) |
| `p_required_permissions` | `text[]` | No (default NULL) | Array of permission keys user must have (uses OR logic, NOT AND) |

### Return Value

| Type | Value | Meaning |
|------|-------|---------|
| `uuid` | user_id | Session valid, user has all required permissions |
| Exception | `invalid_session` | Token not found, expired, or revoked |
| Exception | `permission_denied` | User lacks one or more required permissions |

---

## Expected Behavior

### Scenario 1: Validate Token Only (No Permissions)
```sql
v_uid := require_session_permissions(p_token, NULL);
-- OR
v_uid := require_session_permissions(p_token);
```

**Logic**:
1. SELECT `user_id`, `expires_at`, `revoked_at` FROM `sessions` WHERE `token = p_token`
2. IF token not found:
   - RAISE EXCEPTION 'invalid_session'
3. IF `expires_at < NOW()`:
   - RAISE EXCEPTION 'invalid_session'
4. IF `revoked_at IS NOT NULL`:
   - RAISE EXCEPTION 'invalid_session'
5. RETURN `user_id`

**Use Case**: Staff functions that just need to know "who is calling me?"

---

### Scenario 2: Validate Token + Check Permissions (Non-Admin)
```sql
v_uid := require_session_permissions(p_token, ARRAY['manage_shifts']);
```

**Logic** (assuming user is NOT admin):
1. Validate token (same as Scenario 1)
2. SELECT `is_admin` FROM `users` WHERE `id = v_uid`
3. IF `is_admin = true`:
   - Skip permission checks, RETURN `v_uid` (admin bypass)
4. ELSE (non-admin):
   - SELECT ARRAY_AGG(permission_key) FROM `user_permission_assignments` 
     JOIN `permission_group_permissions` ON `group_id`
     WHERE `user_id = v_uid`
   - Check if returned array contains ALL required permissions
   - IF any required permission is missing:
     - RAISE EXCEPTION 'permission_denied'
   - ELSE:
     - RETURN `v_uid`

**Use Case**: Admin functions where non-admins need explicit permission, but admins bypass checks

---

### Scenario 3: Admin Bypass (User is `is_admin=true`)
```sql
v_uid := require_session_permissions(p_token, ARRAY['manage_shifts']);
```

**Logic** (assuming user IS admin):
1. Validate token (same as Scenario 1)
2. SELECT `is_admin` FROM `users` WHERE `id = v_uid`
3. IF `is_admin = true`:
   - **SKIP permission checks entirely**
   - RETURN `v_uid` (admin has all permissions implicitly)
4. ELSE:
   - Check permissions (see Scenario 2)

**Key Point**: `is_admin` bypass DOES NOT skip token validation. Token is ALWAYS checked first.

---

## Implementation Template

```sql
CREATE OR REPLACE FUNCTION public.require_session_permissions(
  p_token uuid,
  p_required_permissions text[] DEFAULT NULL::text[]
)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user_id uuid;
  v_expires_at timestamp with time zone;
  v_revoked_at timestamp with time zone;
  v_is_admin boolean;
  v_user_perms text[];
  v_missing_perms text[];
  v_perm text;
BEGIN
  -- Step 1: Validate token and get user_id
  SELECT user_id, expires_at, revoked_at
  INTO v_user_id, v_expires_at, v_revoked_at
  FROM public.sessions
  WHERE token = p_token;
  
  -- If token not found
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'invalid_session';
  END IF;
  
  -- If token expired
  IF v_expires_at < NOW() THEN
    RAISE EXCEPTION 'invalid_session';
  END IF;
  
  -- If token revoked
  IF v_revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'invalid_session';
  END IF;
  
  -- Step 2: If no permissions required, return user_id
  IF p_required_permissions IS NULL 
     OR array_length(p_required_permissions, 1) IS NULL 
     OR array_length(p_required_permissions, 1) = 0 THEN
    RETURN v_user_id;
  END IF;
  
  -- Step 3: Check if user is admin (bypass permission checks if true)
  SELECT is_admin
  INTO v_is_admin
  FROM public.users
  WHERE id = v_user_id;
  
  -- Admin bypass: skip permission checks
  IF COALESCE(v_is_admin, false) THEN
    RETURN v_user_id;
  END IF;
  
  -- Step 4: Non-admin: get user's permissions
  SELECT ARRAY_AGG(pgp.permission_key)
  INTO v_user_perms
  FROM public.user_permission_assignments upa
  JOIN public.permission_group_permissions pgp 
    ON pgp.group_id = upa.group_id
  WHERE upa.user_id = v_user_id;
  
  -- Initialize missing perms array
  v_missing_perms := ARRAY[]::text[];
  
  -- Step 5: Check each required permission
  FOREACH v_perm IN ARRAY p_required_permissions
  LOOP
    IF v_user_perms IS NULL 
       OR NOT (v_perm = ANY(v_user_perms)) THEN
      v_missing_perms := array_append(v_missing_perms, v_perm);
    END IF;
  END LOOP;
  
  -- Step 6: Raise exception if any permission missing
  IF array_length(v_missing_perms, 1) > 0 THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;
  
  -- All checks passed
  RETURN v_user_id;
END;
$$;
```

---

## Table Dependencies

This function requires these tables to exist:

### `sessions` Table
```sql
CREATE TABLE public.sessions (
  token uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at timestamp with time zone NOT NULL,
  revoked_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT NOW(),
  updated_at timestamp with time zone DEFAULT NOW()
);
```

**Critical Columns**:
- `token`: Session token (what caller passes as `p_token`)
- `user_id`: User who owns this session
- `expires_at`: Session expiration time
- `revoked_at`: If NOT NULL, session is invalidated

### `users` Table
```sql
CREATE TABLE public.users (
  id uuid PRIMARY KEY,
  name text NOT NULL,
  role_id integer,
  is_admin boolean DEFAULT false,
  preferred_lang text,
  ... other columns ...
);
```

**Critical Column**:
- `is_admin`: If true, user bypasses permission checks

### `user_permission_assignments` Table
```sql
CREATE TABLE public.user_permission_assignments (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  group_id integer NOT NULL REFERENCES permission_groups(id),
  created_at timestamp with time zone DEFAULT NOW(),
  PRIMARY KEY (user_id, group_id)
);
```

### `permission_group_permissions` Table
```sql
CREATE TABLE public.permission_group_permissions (
  group_id integer NOT NULL REFERENCES permission_groups(id) ON DELETE CASCADE,
  permission_key text NOT NULL,
  PRIMARY KEY (group_id, permission_key)
);
```

**Critical Column**:
- `permission_key`: Permission identifier (e.g., `manage_shifts`, `notices.create`)

---

## Pre-Migration Verification

Before running the token-only RPC migration, verify this function exists:

```sql
-- Check if function exists
SELECT COUNT(*) as func_count
FROM pg_proc
WHERE proname = 'require_session_permissions'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
-- Expected: 1

-- View function definition
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'require_session_permissions'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
-- Expected: Function source code

-- Verify function is SECURITY DEFINER
SELECT prosecdef
FROM pg_proc
WHERE proname = 'require_session_permissions'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
-- Expected: t (true)

-- Test function with valid token
SELECT require_session_permissions('valid-token-uuid'::uuid, NULL);
-- Expected: Returns user_id (uuid)

-- Test function with invalid token
SELECT require_session_permissions('00000000-0000-0000-0000-000000000000'::uuid, NULL);
-- Expected: EXCEPTION: invalid_session
```

---

## Troubleshooting

### Issue: Function doesn't exist
**Solution**: Create it using the template above before running migration

### Issue: Function returns wrong user_id
**Solution**: Check that `sessions.user_id` column is correctly populated

### Issue: Admin bypass not working
**Solution**: Verify that:
1. User's `is_admin = true` in users table
2. Function checks `is_admin` before checking permissions (line 71-74 in template)

### Issue: Permission checks failing for valid users
**Solution**: Verify that:
1. Permission keys in `permission_group_permissions` match keys used in migration (see MIGRATION_REVIEW_CHECKLIST.md)
2. User is assigned to correct permission groups via `user_permission_assignments`

### Issue: Permission denied for admin
**Solution**: If admin gets `permission_denied`, check:
1. Is `is_admin = true` in database?
2. Has token expired?
3. Is function being called twice (second call with permissions)?

---

## Examples

### Example 1: Staff user fetching notices
```sql
-- In get_unread_notices() function:
v_uid := require_session_permissions(p_token, NULL);
-- p_token is valid -> returns user_id
-- p_token is invalid/expired -> EXCEPTION 'invalid_session'
-- Result: v_uid is used to filter notices for that user
```

### Example 2: Admin approving swap
```sql
-- In admin_approve_swap_request() function:
v_admin_uid := require_session_permissions(p_token, NULL);
-- p_token is valid -> returns user_id

SELECT is_admin INTO v_is_admin FROM users WHERE id = v_admin_uid;

IF NOT v_is_admin THEN
  PERFORM require_session_permissions(p_token, ARRAY['manage_shifts']);
  -- If user lacks manage_shifts permission -> EXCEPTION 'permission_denied'
  -- If user has manage_shifts permission -> returns user_id (succeeds)
END IF;
-- If is_admin = true -> second call never made (admin bypasses)

-- Result: If reached this point, user is authorized to approve swap
```

### Example 3: Non-admin without permission
```sql
-- Same as Example 2, but user is non-admin without manage_shifts

v_admin_uid := require_session_permissions(p_token, NULL);
-- Returns user_id (token is valid)

SELECT is_admin INTO v_is_admin FROM users WHERE id = v_admin_uid;
-- is_admin = false

IF NOT v_is_admin THEN
  PERFORM require_session_permissions(p_token, ARRAY['manage_shifts']);
  -- User doesn't have manage_shifts -> EXCEPTION 'permission_denied'
  -- Function execution stops here
END IF;
```

---

## Performance Considerations

- **Stable function**: Declare as `STABLE` (output depends only on inputs, not table state) for query optimization
- **Index on sessions.token**: Ensure fast lookup
  ```sql
  CREATE INDEX idx_sessions_token ON sessions(token) WHERE revoked_at IS NULL;
  ```
- **Cache permission lookups**: If performance critical, consider materialized view for user permissions

---

## Security Notes

1. **SECURITY DEFINER**: Function executes with function owner's privileges (usually postgres), not caller's. This allows function to read users/sessions without caller having direct access.

2. **search_path**: SET to ('public', 'pg_temp') prevents attack via malicious temporary functions or missing table lookup.

3. **No direct table writes**: Function is READ-ONLY, only returns data. Safe to call from any context.

4. **Token in URL/logs**: Be aware that `p_token` might appear in Supabase logs. Tokens should be treated like passwords (short-lived, 8-hour expiry recommended).

---

## Compatibility Notes

- PostgreSQL 12+
- Supabase (any recent version)
- No special extensions required (uses standard plpgsql)

---

**Document Version**: 1.0  
**Last Updated**: 2026-01-16  
**Status**: Specification Ready ✅

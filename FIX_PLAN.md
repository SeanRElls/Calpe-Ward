# Security Audit Fix Plan
**Date:** January 16, 2026  
**Priority:** CRITICAL - Deploy ASAP  

---

## Summary of Findings (Updated with Codex Audit)

### Critical Issues (Fix Immediately)

1. **4 Legacy Functions Exist** - Allow user impersonation (p_admin_user_id without session validation)
   - `admin_create_next_period(p_admin_user_id uuid)`
   - `admin_set_active_period(p_admin_user_id uuid, p_period_id bigint)`
   - `admin_set_period_hidden(p_admin_user_id uuid, p_period_id bigint, p_hidden boolean)`
   - `admin_set_week_open(p_admin_user_id uuid, p_week_id bigint, p_open boolean)`
   - **Fix:** Deploy [DROP_LEGACY_ADMIN_FUNCTIONS.sql](sql/DROP_LEGACY_ADMIN_FUNCTIONS.sql)

2. **Token-Only Standard Violations** - Functions accepting p_user_id from client
   - `get_notices_for_user(p_token)` - doesn't call require_session_permissions
   - `upsert_week_comment(p_token, p_week_id, p_user_id, p_comment)` - accepts client p_user_id
   - `set_user_active(p_token, p_user_id, p_active)` - accepts client p_user_id, lacks admin_ prefix
   - **Fix:** Patch functions to derive user_id from token only

3. **GRANT ALL to anon/authenticated** - Allows direct table manipulation on 30+ tables
   - Critical tables: sessions, users, requests, swap_requests, swap_executions, notice_ack
   - **Fix:** REVOKE ALL, grant EXECUTE on functions only

4. **Frontend Calls Legacy/Non-Existent Functions** - 100+ lines passing p_user_id/p_pin
   - verify_user_pin (12 calls), set_user_pin (3 calls), verify_login (1 call)
   - **Fix:** Migrate to token-only RPCs with new helper functions

5. **verify_login Bug** - Ambiguous column references prevent login
   - **Fix:** Deploy [FIX_VERIFY_LOGIN.sql](sql/FIX_VERIFY_LOGIN.sql)

6. **Missing RPC** - admin_get_swap_executions called in frontend but not in database
   - **Fix:** Create missing function or remove frontend calls

---

## Fix Execution Order

**CRITICAL RULE:** Deploy in exact order to avoid breaking dependencies.

---

## Phase 1: Database Hardening (IMMEDIATE)

### Step 1.1: Drop Legacy Admin Functions + PIN-Based RPCs ⚡ HIGHEST PRIORITY

**File:** [sql/DROP_LEGACY_ADMIN_FUNCTIONS.sql](sql/DROP_LEGACY_ADMIN_FUNCTIONS.sql) (EXTENDED)

**Purpose:** Remove ALL legacy functions that allow user impersonation or PIN-based auth

**Impact:** 🟢 LOW RISK - Token-only equivalents already exist

**IMPORTANT:** Also drop any _with_pin, *_pin_*, assert_admin, etc. functions if they exist

**Deployment:**
```powershell
$DB_URL="postgresql://postgres.pxpjxyfcydiasrycpbfp:XKZEOSXO8NhkcaXz@aws-1-eu-west-1.pooler.supabase.com:5432/postgres"
psql $DB_URL -f "sql/DROP_LEGACY_ADMIN_FUNCTIONS.sql"
```

**Extended SQL (via Supabase SQL Editor):**
```sql
BEGIN;

-- Legacy admin overloads (p_admin_user_id)
DROP FUNCTION IF EXISTS public.admin_create_next_period(uuid);
DROP FUNCTION IF EXISTS public.admin_set_active_period(uuid, bigint);
DROP FUNCTION IF EXISTS public.admin_set_period_hidden(uuid, bigint, boolean);
DROP FUNCTION IF EXISTS public.admin_set_week_open(uuid, bigint, boolean);

-- Legacy PIN-based auth (if they exist - may already be dropped)
DROP FUNCTION IF EXISTS public.verify_pin_login(uuid, text);
DROP FUNCTION IF EXISTS public.verify_user_pin(uuid, text);
DROP FUNCTION IF EXISTS public.verify_admin_pin(uuid, text);
DROP FUNCTION IF EXISTS public._require_admin(uuid, text);
DROP FUNCTION IF EXISTS public.assert_admin(uuid, text);

-- Legacy _with_pin variants (if they exist)
DROP FUNCTION IF EXISTS public.clear_request_with_pin(uuid, text, date);
DROP FUNCTION IF EXISTS public.delete_request_with_pin(uuid, text, date);
DROP FUNCTION IF EXISTS public.save_request_with_pin(uuid, text, date, text, integer);
DROP FUNCTION IF EXISTS public.upsert_request_with_pin(uuid, text, date, text, integer);

COMMIT;
```

**Verification:**
```sql
-- Should return 0 rows
SELECT routine_name, string_agg(parameter_name, ', ' ORDER BY ordinal_position) as parameters
FROM information_schema.routines r
LEFT JOIN information_schema.parameters p ON r.specific_name = p.specific_name
WHERE routine_schema = 'public'
  AND routine_name IN ('admin_create_next_period', 'admin_set_active_period', 
                       'admin_set_period_hidden', 'admin_set_week_open')
GROUP BY routine_name;
```

**Expected:** Only token-based versions remain (p_token as first parameter)

**Rollback Plan:** N/A - functions are deprecated, no rollback needed

---

### Step 1.2: Fix verify_login Ambiguous Column Bug ⚡ HIGH PRIORITY

**File:** [sql/FIX_VERIFY_LOGIN.sql](sql/FIX_VERIFY_LOGIN.sql)

**Purpose:** Fix ambiguous column references preventing login from working

**Impact:** 🟢 LOW RISK - Fixes existing broken function

**Deployment:**
```powershell
psql $DB_URL -f "sql/FIX_VERIFY_LOGIN.sql"
```

**Verification:**
```sql
-- Test login with real username/PIN
SELECT * FROM public.verify_login('your_username', '1234', 'test_ip', 'test_ua');
-- Expected: Valid token OR specific error (NOT "column ambiguous")
```

**Rollback Plan:**
```sql
-- Restore previous version from backup if needed
-- (Previous version had ambiguous columns, so rollback = broken state)
```

---

### Step 1.3: Fix Token-Only Standard Violations ⚡ HIGH PRIORITY

**File:** Create new file `sql/FIX_TOKEN_ONLY_VIOLATIONS.sql`

**Purpose:** Fix 3 functions that violate token-only standard

**Impact:** 🟡 MEDIUM RISK - May break frontend calls, test thoroughly

**SQL to create:**
```sql
-- ============================================================================
-- FIX TOKEN-ONLY VIOLATIONS
-- ============================================================================
-- Fix functions that accept p_user_id or don't validate sessions properly
-- ============================================================================

BEGIN;

-- 1. Fix get_notices_for_user to validate session
CREATE OR REPLACE FUNCTION public.get_notices_for_user(p_token uuid)
RETURNS TABLE(
  id uuid,
  title text,
  body_en text,
  body_es text,
  version integer,
  is_active boolean,
  updated_at timestamptz,
  created_by uuid,
  created_by_name text,
  target_all boolean,
  target_roles integer[],
  acknowledged_at timestamptz,
  ack_version integer
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
BEGIN
  -- FIX: Add session validation
  v_uid := public.require_session_permissions(p_token, null);

  RETURN QUERY
  SELECT
    n.id,
    n.title,
    n.body_en,
    n.body_es,
    n.version,
    n.is_active,
    n.updated_at,
    n.created_by,
    u.name as created_by_name,
    n.target_all,
    COALESCE(array_agg(nt.role_id) FILTER (WHERE nt.role_id IS NOT NULL), '{}'::integer[]) as target_roles,
    na.acknowledged_at,
    na.version as ack_version
  FROM public.notices n
  LEFT JOIN public.users u ON u.id = n.created_by
  LEFT JOIN public.notice_targets nt ON nt.notice_id = n.id
  LEFT JOIN public.notice_ack na ON na.notice_id = n.id AND na.user_id = v_uid
  WHERE n.is_active = true
  GROUP BY n.id, u.id, na.user_id, na.acknowledged_at, na.version
  ORDER BY n.updated_at DESC;
END;
$$;
psql $DB_URL -f "sql/REVOKE_TABLE_GRANTS.sql"
```

**CRITICAL:** Do NOT deploy this until Phase 2 frontend migration is complete!ATE OR REPLACE FUNCTION public.upsert_week_comment(
  p_token uuid,
  p_week_id uuid,
  p_comment text  -- REMOVED p_user_id parameter
) 
RETURNS TABLE(user_id uuid, week_id uuid, comment text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
  v_result RECORD;
BEGIN
  -- FIX: Derive user_id from token instead of accepting from client
  v_uid := public.require_session_permissions(p_token, null);

  INSERT INTO public.week_comments (week_id, user_id, comment)
  VALUES (p_week_id, v_uid, p_comment)
  ON CONFLICT (week_id, user_id) DO UPDATE SET comment = p_comment
  RETURNING * INTO v_result;

  RETURN QUERY SELECT v_result.user_id, v_result.week_id, v_result.comment;
END;
$$;

-- 3. Rename set_user_active to admin_set_user_active (admin function without admin_ prefix)
-- Keep old version temporarily for backwards compatibility
CREATE OR REPLACE FUNCTION public.admin_set_user_active(
  p_token uuid,
  p_target_user_id uuid,  -- Renamed from p_user_id for clarity
  p_active boolean
) 
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);
  
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['users.edit']);
  END IF;

  UPDATE public.users SET is_active = p_active WHERE id = p_target_user_id;
END;
$$;

-- Keep old name as alias for now (mark for deprecation)
CREATE OR REPLACE FUNCTION public.set_user_active(
  p_token uuid,
  p_user_id uuid,
  p_active boolean
) 
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- Delegate to new function
  PERFORM public.admin_set_user_active(p_token, p_user_id, p_active);
END;
$$;

COMMIT;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- Check new signatures:
SELECT routine_name, pg_get_function_identity_arguments(p.oid) 
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND routine_name IN ('get_notices_for_user', 'upsert_week_comment', 'set_user_active', 'admin_set_user_active');
```

**Deployment:**
```powershell
psql $DB_URL -f "sql/FIX_TOKEN_ONLY_VIOLATIONS.sql"
```

**Frontend Impact:** 
- `upsert_week_comment` calls must remove `p_user_id` parameter
- `set_user_active` still works (backward compatible)

---

### Step 1.4: Revoke Direct Table Access ⚡ CRITICAL PRIORITY

**File:** Create new file `sql/REVOKE_TABLE_GRANTS.sql`

**Purpose:** Remove ALL grants on sensitive tables to prevent direct manipulation

**Impact:** 🔴 **HIGH RISK** - May break direct table queries in frontend

**IMPORTANT:** Audit all frontend `.from()` calls BEFORE deploying (see Phase 2)

**SQL to create:**
```sql
-- ============================================================================
-- REVOKE TABLE GRANTS - Force RPC-Only Access
-- ============================================================================
-- WARNING: This will break any direct table queries in the frontend
-- Audit all .from() calls before deploying
-- ============================================================================

BEGIN;

-- Revoke ALL table access from anon and authenticated roles
DO $$
DECLARE
  tbl RECORD;
BEGIN
  FOR tbl IN 
    SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  LOOP
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM anon', tbl.tablename);
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM authenticated', tbl.tablename);
  END LOOP;
END $$;

-- Grant EXECUTE on all functions (RPC-only access)
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- Grant SELECT on reference tables (read-only lookups)
GRANT SELECT ON public.roles TO anon, authenticated;
GRANT SELECT ON public.shifts TO anon, authenticated;
GRANT SELECT ON public.permissions TO anon, authenticated;
GRANT SELECT ON public.permission_groups TO anon, authenticated;
GRANT SELECT ON public.pattern_definitions TO anon, authenticated;

-- Grant SELECT on rota structure (needed for calendar display)
GRANT SELECT ON public.rota_periods TO anon, authenticated;
GRANT SELECT ON public.rota_weeks TO anon, authenticated;
GRANT SELECT ON public.rota_dates TO anon, authenticated;
GRANT SELECT ON public.rota_assignments TO anon, authenticated;

COMMIT;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- Check for remaining non-SELECT grants:
SELECT grantee, privilege_type, table_name
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND grantee IN ('anon', 'authenticated')
  AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE')
ORDER BY table_name;
-- Expected: 0 rows
```

**Deployment:**
```powershell
# Create the file
psql $DB_URL -f "sql/REVOKE_TABLE_GRANTS.sql"
```

**Verification:**
```sql
-- Check grants
SELECT grantee, privilege_type, table_name
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND grantee IN ('anon', 'authenticated')
ORDER BY table_name, privilege_type;
-- Expected: Only SELECT on reference tables, EXECUTE on functions
```

**Rollback Plan:**
```sql
-- Restore original grants (if needed)
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
```

---

## Phase 2: Frontend Migration (THIS WEEK)
Create Missing admin_get_swap_executions RPC

**Issue:** Frontend calls this function but it doesn't exist in database

**File:** Create `sql/CREATE_ADMIN_GET_SWAP_EXECUTIONS.sql`

**SQL:**
```sql
CREATE OR REPLACE FUNCTION public.admin_get_swap_executions(p_token uuid)
RETURNS TABLE(
  id uuid,
  period_id integer,
  method text,
  initiator_user_id uuid,
  initiator_name text,
  counterparty_user_id uuid,
  counterparty_name text,
  authoriser_user_id uuid,
  authoriser_name text,
  initiator_shift_date date,
  counterparty_shift_date date,
  executed_at timestamptz,
  created_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);
  
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['manage_shifts']);
  END IF;

  RETURN QUERY
  SELECT 
    se.id,
    se.period_id,
    se.method,
    se.initiator_user_id,
    se.initiator_name,
    se.counterparty_user_id,
    se.counterparty_name,
    se.authoriser_user_id,
    se.authoriser_name,
    se.initiator_shift_date,
    se.counterparty_shift_date,
    se.executed_at,
    se.created_at
  FROM public.swap_executions se
  ORDER BY se.executed_at DESC;
END;
$$;
```

**Deployment:**
```powershell
psql $DB_URL -f "sql/CREATE_ADMIN_GET_SWAP_EXECUTIONS.sql"
```

---

### Step 2.2: Replace verify_user_pin Calls

**Files to modify (12 instances):**
1. [js/admin.js#L235](js/admin.js#L235)
2. [js/app.js#L1138](js/app.js#L1138)
3. [js/app.3: Replace set_user_pin Calls

**Files to modify (3 instances):**
1. [js/admin.js#L588](js/admin.js#L588)
2. [js/app.js#L3093](js/app.js#L3093)
3. Plus 1 more in index.html (see codex audit
```javascript
const { data: ok, error: vErr } = await supabaseClient.rpc("verify_user_pin", {
  p_user_id: userId,
  p_pin: pin
});
```

**New Code (WORKING):**
```javascript
// Option 1: If verifying current user's PIN for sensitive operation
const { data: ok, error: vErr } = await supabaseClient.rpc("change_user_pin", {
  p_token: currentToken,
  p_old_pin: pin,
  p_new_pin: pin  // Same PIN = verify only
});
// Success = valid PIN, error = invalid PIN

// Option 2: Admin verifying any user's PIN (NEEDS NEW RPC)
// Create admin_verify_user_pin(p_token, p_target_user_id, p_pin)
// (Requires new function in database)
```

**Recommended:** Create new RPC `admin_verify_user_pin(p_token uuid, p_target_user_id uuid, p_pin text)` for admin use cases

**SQL for new function:**
```sql
CREATE OR REPLACE FUNCTION public.admin_verify_user_pin(
  p_token uuid,
  p_target_user_id uuid,
  p_pin text
)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
  v_pin_hash text;
BEGIN
  -- Validate admin session
  v_admin_uid := public.require_session_permissions(p_token, null);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['users.edit']);
  END IF;

  -- Verify target user's PIN
  SELECT pin_hash INTO v_pin_hash FROM public.users WHERE id = p_target_user_id;
  
  IF v_pin_hash IS NULL THEN
    RETURN false;
  END IF;

  RETURN v_4: Fix upsert_week_comment Calls (Remove p_user_id)

**Files to modify:**
- Search for all `upsert_week_comment` calls
- Remove `p_user_id` parameter (now derived from token)

**Example:**
```javascript
// OLD
await supabaseClient.rpc('upsert_week_comment', {
  p_token: currentToken,
  p_week_id: weekId,
  p_user_id: currentUserId,  // ❌ REMOVE THIS
  p_comment: 'My comment'
});

// NEW
await supabaseClient.rpc('upsert_week_comment', {
  p_token: currentToken,
  p_week_id: weekId,
  p_comment: 'My comment'
});
```

---

### Step 2.5: Audit Direct Table Queries

**Issue:** Frontend has 50+ direct table queries on sensitive tables

**Critical Violations (from codex audit):**
- Direct writes to `users`, `requests`, `request_cell_locks`, `week_comments`, `notices`, `notifications`
- Permission table manipulation: `user_permission_groups`, `permission_group_permissions`

**Files with most violations:**
- `js/admin.js` - 15+ direct table queries
- `js/app.js` - 20+ direct table queries
- `index.html` - 15+ direct table queries

**Action Required:**
1. Audit each `.from()` call
2. For **READ** operations on reference tables (roles, shifts, permissions) - ✅ ALLOWED
3. For **WRITE** operations (insert/update/delete) - ❌ REPLACE with RPC
4. For **READ** on sensitive tables (users, sessions) - Consider replacing with RPC

**Priority Fixes:**
```javascript
// HIGH PRIORITY - Direct permission manipulation
// js/admin.js:1224, 1227, 1331, 1334
await supabaseClient.from("permission_group_permissions").delete()...
await supabaseClient.from("user_permission_groups").delete()...
// FIX: Create admin_set_user_permissions(p_token, p_user_id, p_group_ids[]) RPC

// MEDIUM PRIORITY - Direct user updates  
// Multiple files
await supabaseClient.from("users").update(...)...
// FIX: Use admin_upsert_user or admin_set_user_active

// LOW PRIORITY - Reference data reads (OK for now)
await supabaseClient.from("roles").select()...
await supabaseClient.from("shifts").select()...
```
**Current Code (BROKEN):**
```javascript
const { error } = await supabaseClient.rpc("set_user_pin", {
  p_user_id: userId,
  p_pin: pin
});
```

**New Code (NEEDS NEW RPC):**
```javascript
const { error } = await supabaseClient.rpc("admin_set_user_pin", {
  p_token: currentToken,
  p_target_user_id: userId,
  p_new_pin: pin
});
```

**SQL for new function:**
```sql
CREATE OR REPLACE FUNCTION public.admin_set_user_pin(
  p_token uuid,
  p_target_user_id uuid,
  p_new_pin text
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
  v_pin_hash text;
BEGIN
  -- Validate admin session
  v_admin_uid := public.require_session_permissions(p_token, null);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['users.edit']);
  END IF;

  -- Validate PIN format
  IF p_new_pin IS NULL OR p_new_pin = '' OR length(p_new_pin) != 4 OR NOT p_new_pin ~ '^\d{4}$' THEN
    RAISE EXCEPTION 'PIN must be 4 digits';
  END IF;

  -- Hash and update
  v_pin_hash := public.crypt(p_new_pin, public.gen_salt('bf', 4));
  UPDATE public.users SET pin_hash = v_pin_hash WHERE id = p_target_user_id;
END;
$$;
```

---

### Step 2.3: Audit Direct Table Queries

**Command:**
```powershell
# Search for all .from() calls
grep -rn "\.from\(.*\)\.(insert|update|delete|upsert)" js/*.js
```

**Expected:** NO direct writes to sensitive tables (sessions, users, requests, swap_requests, etc.)

**Allowed:** Direct reads (SELECT) for reference data

**Fix:** Replace direct writes with RPC calls

---

## Phase 3: RLS Hardening (NEXT SPRINT)

### Step 3.1: Enable RLS on Sensitive Tables

**File:** `sql/ENABLE_RLS_SENSITIVE_TABLES.sql`

```sql
-- Enable RLS on session-critical tables
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_rate_limiting ENABLE ROW LEVEL SECURITY;

-- Enable RLS on swap tables
ALTER TABLE public.swap_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.swap_executions ENABLE ROW LEVEL SECURITY;

-- Enable RLS on assignment tables
ALTER TABLE public.rota_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rota_assignment_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rota_assignment_overrides ENABLE ROW LEVEL SECURITY;
```

### Step 3.2: Create RLS Policies

**File:** `sql/CREATE_RLS_POLICIES.sql`

```sql
-- Block ALL direct access to sessions table
CREATE POLICY "block_all_sessions" ON public.sessions FOR ALL USING (false);

-- Block ALL direct access to users table
CREATE POLICY "block_all_users" ON public.users FOR ALL USING (false);

-- Allow read-only access to own user record (for session validation)
CREATE POLICY "read_own_user" ON public.users FOR SELECT
USING (id = (SELECT user_id FROM public.sessions WHERE token = current_setting('request.jwt.claims', true)::json->>'token'));

-- Block direct access to login tables
CREATE POLICY "block_login_audit" ON public.login_audit FOR ALL USING (false);
CREATE POLICY "block_rate_limiting" ON public.login_rate_limiting FOR ALL USING (false);

-- Block direct access to swap tables
CREATE POLICY "block_swap_requests" ON public.swap_requests FOR ALL USING (false);
CREATE POLICY "block_swap_executions" ON public.swap_executions FOR ALL USING (false);

-- Block direct writes to assignments (read via RPCs only)
CREATE POLICY "block_assignment_writes" ON public.rota_assignments FOR INSERT USING (false);
CREATE POLICY "block_assignment_updates" ON public.rota_assignments FOR UPDATE USING (false);
CREATE POLICY "block_assignment_deletes" ON public.rota_assignments FOR DELETE USING (false);
```

**Note:** RLS is defense-in-depth. With REVOKE grants, (extended version)
- [ ] Step 1.1: Verify ALL legacy functions dropped (run verification query)
- [ ] Step 1.2: Deploy FIX_VERIFY_LOGIN.sql
- [ ] Step 1.2: Test login with real credentials
- [ ] Step 1.3: Deploy FIX_TOKEN_ONLY_VIOLATIONS.sql
- [ ] Step 1.3: Verify function signatures updated
- [ ] Step 1.4: Create REVOKE_TABLE_GRANTS.sql
- [ ] Step 1.4
### Step 4.1: Session Monitoring
get_swap_executions function
- [ ] Step 2.1: Deploy to database and verify
- [ ] Step 2.2: Create admin_verify_user_pin function
- [ ] Step 2.2: Create admin_set_user_pin function
- [ ] Step 2.2: Deploy new helper functions to database
- [ ] Step 2.3: Update all 12 verify_user_pin calls in frontend
- [ ] Step 2.3: Update all 3 set_user_pin calls in frontend
- [ ] Step 2.4: Update all upsert_week_comment calls (remove p_user_id)
- [ ] Step 2.5: Audit all .from() calls for direct writes
- [ ] Step 2.5: Create RPCs for permission management (high priority)
- [ ] Step 2.5: Replace critical direct writes with RPCs
- [ ] Step 2.5: Test all frontend functionality thoroughly
- [ ] **NOW SAFE:** Step 1.4: Deploy REVOKE_TABLE_GRANTS.sql
- [ ] Step 1.4: Verify grants revoked
- [ ] Step 1.4imestamptz DEFAULT now()
);

-- Trigger to log session events
-- (Implementation left for Phase 4)
```

### Step 4.2: Session Rotation

**Implement:** Rotate token on privilege escalation (e.g., user becomes admin)

### Step 4.3: RPC Rate Limiting

**Implement:** Rate limiting per token (e.g., max 100 RPC calls per minute)

### Step 4.4: Permission Data Audit

**Verify:** All permission groups have correct permissions assigned

---

## Deployment Checklist

### Pre-Deployment

- [ ] Read entire fix plan
- [ ] Backup database (`pg_dump`)
- [ ] Test on staging environment (if available)
- [ ] Notify team of deployment window

### Phase 1 Deployment (IMMEDIATE)

- [ ] Step 1.1: Deploy DROP_LEGACY_ADMIN_FUNCTIONS.sql
- [ ] Step 1.1: Verify legacy functions dropped
- [ ] Step 1.2: Deploy FIX_VERIFY_LOGIN.sql
- [ ] Step 1.2: Test login with real credentials
- [ ] Step 1.3: Create REVOKE_TABLE_GRANTS.sql
- [ ] Step 1.3: **WAIT - Complete Phase 2 first** ⚠️

### Phase 2 Deployment (THIS WEEK)

- [ ] Step 2.1: Create admin_verify_user_pin function
- [ ] Step 2.1: Create admin_set_user_pin function
- [ ] Step 2.1: Deploy new functions to database
- [ ] Step 2.2: Update js/admin.js (replace verify_user_pin calls)
- [ ] Step 2.2: Update js/app.js (replace verify_user_pin calls)
- [ ] Step 2.2: Update js/app.js (replace set_user_pin calls)
- [ ] Step 2.3: Audit all .from() calls for direct writes
- [ ] Step 2.3: Replace direct writes with RPCs
- [ ] Step 2.3: Test all frontend functionality
- [ ] **NOW SAFE:** Step 1.3: Deploy REVOKE_TABLE_GRANTS.sql
- [ ] Step 1.3: Verify grants revoked
- [ ] Step 1.3: Test entire application (no direct table access)

### Phase 3 Deployment (NEXT SPRINT)

- [ ] Step 3.1: Deploy ENABLE_RLS_SENSITIVE_TABLES.sql
- [ ] Step 3.2: Deploy CREATE_RLS_POLICIES.sql
- [ ] Test application with RLS enabled

### Phase 4 (BACKLOG)run full inventory query)
- [ ] verify_login works without ambiguous column errors
- [ ] get_notices_for_user validates session via require_session_permissions
- [ ] upsert_week_comment derives user_id from token (doesn't accept p_user_id)
- [ ] admin_set_user_active exists and works
- [ ] admin_get_swap_executions exists and returns data
- [ ] No GRANT INSERT/UPDATE/DELETE on sensitive tables (Phase 1.4 pending)
- [ ] Implement session rotation
- [ ] Implement RPC rate limiting
- [ ] Audit permission data

---

## Rollback Procedures

### Rollback Phase 1.1 (Drop Legacy Functions)
```sql
-- N/A - Functions deprecated, no rollback needed
-- If needed, restore from backup
```

### Rollback Phase 1.2 (Fix verify_login)
```sql
-- Restore previous version from backup
-- Note: Previous version was broken (ambiguous columns)
```

### Rollback Phase 1.3 (Revoke Grants)
```sql
-- Restore original grants
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
```

### Rollback Phase 2 (Frontend Migration)
```bash
# Revert git commits
git revert <commit-hash>
```

### Rollback Phase 3 (RLS)
```sql
-- Disable RLS
ALTER TABLE public.sessions DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.users DISABLE ROW LEVEL SECURITY;
-- ... (repeat for all tables)

-- Drop policies
DROP POLICY "block_all_sessions" ON public.sessions;
DROP POLICY "block_all_users" ON public.users;
-- ... (repeat for all policies)
```

---
12 verify_user_pin calls replaced with admin_verify_user_pin
- [ ] All 3 set_user_pin calls replaced with admin_set_user_pin
- [ ] All upsert_week_comment calls updated (p_user_id removed)
- [ ] admin_get_swap_executions working in admin panel
- [ ] Critical direct table writes replaced with RPCs (permissions, users)
- [ ] No remaining p_user_id/p_admin_id/p_pin in frontend RPC calls
- [ ] Login, admin panel, swap requests, notices, and staff features all
### Phase 1 Success
- [ ] 0 legacy functions remain (verify_user_pin, set_user_pin, admin_*_with_user_id)
- [ ] verify_login works without ambiguous column errors
- [ ] No GRANT INSERT/UPDATE/DELETE on sensitive tables

### Phase 2 Success
- [ ] All frontend RPC calls use p_token
- [ ] No .from().insert|update|delete on sensitive tables
- [ ] Login, admin panel, and staff features working

### Phase 3 Success
- [ ] RLS enabled on 32+ tables
- [ ] RLS policies block direct access
- [ ] Application still functional

---

## Support & Troubleshooting

### Issue: "Function does not exist" after Phase 1.1

**Cause:** Frontend still calling legacy functions

**Fix:** Complete Phase 2 frontend migration

### Issue: "Permission denied for table X" after Phase 1.3

**Cause:** Frontend using direct table queries

**Fix:** Replace with RPC calls (see Phase 2.3)

### Issue: Login fails after Phase 1.2

**Cause:** verify_login still has bugs

**Fix:** Check error message, verify FIX_VERIFY_LOGIN.sql deployed correctly

### Issue: Admin features broken after Phase 1.1

**Cause:** Frontend calling legacy admin functions

**Fix:** Update to token-only versions (e.g., admin_set_active_period(p_token, p_period_id))

---

**End of Fix Plan**

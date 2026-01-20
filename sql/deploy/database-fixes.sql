-- ============================================================================
-- COMPREHENSIVE DATABASE FIX DEPLOYMENT
-- ============================================================================
-- Deploy Date: January 16, 2026
-- Priority: CRITICAL
-- 
-- IMPORTANT: This includes Phase 1 + Phase 2 database fixes
-- DO NOT run REVOKE_TABLE_GRANTS section until frontend migration complete
-- ============================================================================

BEGIN;

-- ============================================================================
-- PHASE 1.1: DROP LEGACY FUNCTIONS
-- ============================================================================
-- Remove all legacy admin functions and PIN-based auth functions
-- ============================================================================

-- Legacy admin overloads (p_admin_user_id without token validation)
DROP FUNCTION IF EXISTS public.admin_create_next_period(uuid);
DROP FUNCTION IF EXISTS public.admin_set_active_period(uuid, bigint);
DROP FUNCTION IF EXISTS public.admin_set_period_hidden(uuid, bigint, boolean);
DROP FUNCTION IF EXISTS public.admin_set_week_open(uuid, bigint, boolean);

-- Legacy PIN-based auth functions (if they exist - may already be dropped)
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

-- ============================================================================
-- PHASE 1.2: FIX VERIFY_LOGIN (Ambiguous Column Bug)
-- ============================================================================
-- Fix ambiguous column references in verify_login function
DROP FUNCTION IF EXISTS public.verify_login(text, text, text, text);
-- ============================================================================

CREATE OR REPLACE FUNCTION public.verify_login(
  p_username text,
  p_pin text,
  p_ip_hash text DEFAULT 'unknown'::text,
  p_user_agent_hash text DEFAULT 'unknown'::text
)
RETURNS TABLE(
  token uuid,
  user_id uuid,
  username text,
  name text,
  role_id integer,
  is_admin boolean,
  is_active boolean,
  language text,
  expires_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user_id uuid;
  v_username text;
  v_name text;
  v_role_id integer;
  v_is_admin boolean;
  v_is_active boolean;
  v_language text;
  v_pin_hash text;
  v_token uuid;
  v_expires_at timestamptz;
  v_username_lower text;
  v_failed_attempts integer;
  v_locked_until timestamptz;
BEGIN
  -- Normalize username
  v_username_lower := lower(trim(p_username));

  -- Check rate limiting
  SELECT failed_attempts, locked_until
  INTO v_failed_attempts, v_locked_until
  FROM public.login_rate_limiting AS lrl
  WHERE lrl.username = v_username_lower;

  IF v_locked_until IS NOT NULL AND v_locked_until > now() THEN
    RAISE EXCEPTION 'Account locked due to too many failed attempts. Try again later.';
  END IF;

  -- Get user record (FIXED: qualified column names)
  SELECT u.id, u.username, u.name, u.role_id, u.is_admin, u.is_active, u.language, u.pin_hash
  INTO v_user_id, v_username, v_name, v_role_id, v_is_admin, v_is_active, v_language, v_pin_hash
  FROM public.users AS u
  WHERE lower(u.username) = v_username_lower;

  -- Check if user exists
  IF v_user_id IS NULL THEN
    -- Log failed attempt
    INSERT INTO public.login_audit (username, success, ip_hash, user_agent_hash)
    VALUES (v_username_lower, false, p_ip_hash, p_user_agent_hash);
    
    -- Update rate limiting
    INSERT INTO public.login_rate_limiting (username, failed_attempts, last_failed_at)
    VALUES (v_username_lower, 1, now())
    ON CONFLICT (username) DO UPDATE
    SET failed_attempts = public.login_rate_limiting.failed_attempts + 1,
        last_failed_at = now(),
        locked_until = CASE
          WHEN public.login_rate_limiting.failed_attempts + 1 >= 5 THEN now() + interval '15 minutes'
          ELSE NULL
        END;
    
    RAISE EXCEPTION 'Invalid username or PIN';
  END IF;

  -- Check if user is active
  IF NOT v_is_active THEN
    RAISE EXCEPTION 'User account is inactive';
  END IF;

  -- Verify PIN (FIXED: using v_pin_hash variable)
  IF v_pin_hash IS NULL OR NOT (v_pin_hash = public.crypt(p_pin, v_pin_hash)) THEN
    -- Log failed attempt
    INSERT INTO public.login_audit (user_id, username, success, ip_hash, user_agent_hash)
    VALUES (v_user_id, v_username_lower, false, p_ip_hash, p_user_agent_hash);
    
    -- Update rate limiting (FIXED: qualified lrl.username)
    UPDATE public.login_rate_limiting AS lrl
    SET failed_attempts = lrl.failed_attempts + 1,
        last_failed_at = now(),
        locked_until = CASE
          WHEN lrl.failed_attempts + 1 >= 5 THEN now() + interval '15 minutes'
          ELSE NULL
        END
    WHERE lrl.username = v_username_lower;
    
    RAISE EXCEPTION 'Invalid username or PIN';
  END IF;

  -- PIN verified - create session
  v_token := gen_random_uuid();
  v_expires_at := now() + interval '8 hours';

  INSERT INTO public.sessions (token, user_id, expires_at)
  VALUES (v_token, v_user_id, v_expires_at);

  -- Log successful login
  INSERT INTO public.login_audit (user_id, username, success, ip_hash, user_agent_hash)
  VALUES (v_user_id, v_username_lower, true, p_ip_hash, p_user_agent_hash);

  -- Clear rate limiting (FIXED: qualified lrl.username)
  DELETE FROM public.login_rate_limiting AS lrl
  WHERE lrl.username = v_username_lower;

  -- Return session info
  RETURN QUERY
  SELECT v_token, v_user_id, v_username, v_name, v_role_id, v_is_admin, v_is_active, v_language, v_expires_at;
END;
$$;

-- ============================================================================
-- PHASE 1.3: FIX TOKEN-ONLY VIOLATIONS
-- ============================================================================
-- Fix functions that accept p_user_id or don't validate sessions
-- ============================================================================

-- 1. Fix get_notices_for_user to validate session
DROP FUNCTION IF EXISTS public.get_notices_for_user(uuid, text);
DROP FUNCTION IF EXISTS public.get_notices_for_user(uuid);
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

-- 2. Fix upsert_week_comment to derive user_id from token
DROP FUNCTION IF EXISTS public.upsert_week_comment(uuid, uuid, text, text);
CREATE OR REPLACE FUNCTION public.upsert_week_comment(
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

-- 3. Create admin_set_user_active (proper admin function with admin_ prefix)
CREATE OR REPLACE FUNCTION public.admin_set_user_active(
  p_token uuid,
  p_target_user_id uuid,
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

-- Keep old set_user_active as backward-compatible alias (DEPRECATED)
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

-- ============================================================================
-- PHASE 2.1: CREATE MISSING ADMIN_GET_SWAP_EXECUTIONS
-- ============================================================================
-- Frontend calls this function but it doesn't exist in database
-- ============================================================================

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

-- ============================================================================
-- PHASE 2.2: CREATE ADMIN HELPER FUNCTIONS (verify PIN, set PIN)
-- ============================================================================
-- Replace legacy verify_user_pin and set_user_pin with token-based versions
-- ============================================================================

-- Admin function to verify any user's PIN
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

  -- Get target user's PIN hash
  SELECT pin_hash INTO v_pin_hash FROM public.users WHERE id = p_target_user_id;
  
  IF v_pin_hash IS NULL THEN
    RETURN false;
  END IF;

  -- Verify PIN
  RETURN v_pin_hash = public.crypt(p_pin, v_pin_hash);
END;
$$;

-- Admin function to set any user's PIN
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

COMMIT;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================
-- Run these to confirm deployment succeeded
-- ============================================================================

-- 1. Verify legacy functions are gone (should return 0 rows)
SELECT p.proname AS routine_name, pg_get_function_identity_arguments(p.oid) AS signature
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'admin_create_next_period', 
    'admin_set_active_period', 
    'admin_set_period_hidden', 
    'admin_set_week_open',
    'verify_pin_login',
    'verify_user_pin',
    'verify_admin_pin',
    '_require_admin',
    'assert_admin'
  )
  AND pg_get_function_identity_arguments(p.oid) NOT LIKE '%p_token%';

-- 2. Verify new functions exist (should return 3 rows)
SELECT p.proname AS routine_name, pg_get_function_identity_arguments(p.oid) AS signature
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'admin_get_swap_executions',
    'admin_verify_user_pin',
    'admin_set_user_pin'
  );

-- 3. Verify token-only fixes (should return 3 rows with correct signatures)
SELECT 
  p.proname AS routine_name,
  pg_get_function_identity_arguments(p.oid) AS signature
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('get_notices_for_user', 'upsert_week_comment', 'admin_set_user_active');

-- 4. Test verify_login (replace 'testuser' and '1234' with real values)
-- SELECT * FROM public.verify_login('testuser', '1234', 'test_ip', 'test_ua');

-- ============================================================================
-- NEXT STEPS
-- ============================================================================
-- IMPORTANT: DO NOT run REVOKE_TABLE_GRANTS.sql yet!
-- 
-- Before revoking table grants, you MUST:
-- 1. Update all verify_user_pin calls to admin_verify_user_pin (12 instances)
-- 2. Update all set_user_pin calls to admin_set_user_pin (3 instances)
-- 3. Update all upsert_week_comment calls to remove p_user_id parameter
-- 4. Audit all .from() calls for direct table writes
-- 5. Replace critical direct writes with RPCs
-- 6. Test entire frontend thoroughly
-- 
-- Only AFTER frontend migration is complete and tested:
-- 7. Run REVOKE_TABLE_GRANTS.sql from FIX_PLAN.md
-- ============================================================================

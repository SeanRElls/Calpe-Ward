-- ============================================================================
-- FIX LOGIN SCHEMA AND VERIFY_LOGIN FUNCTION
-- ============================================================================
-- This script fixes the login system by:
-- 1. Creating the required login_audit and login_rate_limiting tables
-- 2. Deploying the corrected verify_login function with proper column names
-- ============================================================================

BEGIN;

-- ============================================================================
-- STEP 1: CREATE REQUIRED TABLES (if not already present)
-- ============================================================================

-- Create login_audit table for security logging
CREATE TABLE IF NOT EXISTS public.login_audit (
  id bigserial PRIMARY KEY,
  user_id uuid,
  username text NOT NULL,
  ip_hash text NOT NULL,
  user_agent_hash text NOT NULL,
  login_at timestamp with time zone NOT NULL DEFAULT NOW(),
  success boolean NOT NULL,
  failure_reason text,
  created_at timestamp with time zone NOT NULL DEFAULT NOW()
);

-- Create login_rate_limiting table for brute force protection
CREATE TABLE IF NOT EXISTS public.login_rate_limiting (
  id bigserial PRIMARY KEY,
  username text NOT NULL,
  ip_hash text NOT NULL,
  attempt_count integer NOT NULL DEFAULT 1,
  first_attempt_at timestamp with time zone NOT NULL DEFAULT NOW(),
  last_attempt_at timestamp with time zone NOT NULL DEFAULT NOW(),
  locked_until timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT NOW(),
  updated_at timestamp with time zone NOT NULL DEFAULT NOW(),
  UNIQUE(username, ip_hash)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_login_audit_user_id_login_at ON public.login_audit(user_id, login_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_audit_ip_hash_login_at ON public.login_audit(ip_hash, login_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_audit_success_login_at ON public.login_audit(success, login_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_rate_limiting_locked_until ON public.login_rate_limiting(locked_until);

-- ============================================================================
-- STEP 2: DROP AND RECREATE VERIFY_LOGIN WITH CORRECT SCHEMA
-- ============================================================================
-- This version uses the correct column names: attempt_count, not failed_attempts
-- ============================================================================

DROP FUNCTION IF EXISTS public.verify_login(text, text, text, text);

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
  v_attempt_count integer;
  v_locked_until timestamptz;
BEGIN
  -- Normalize username
  v_username_lower := lower(trim(p_username));

  -- Check rate limiting
  SELECT attempt_count, locked_until
  INTO v_attempt_count, v_locked_until
  FROM public.login_rate_limiting
  WHERE public.login_rate_limiting.username = v_username_lower AND public.login_rate_limiting.ip_hash = p_ip_hash;

  IF v_locked_until IS NOT NULL AND v_locked_until > now() THEN
    -- Log the rate limit attempt
    INSERT INTO public.login_audit (username, success, ip_hash, user_agent_hash, failure_reason)
    VALUES (v_username_lower, false, p_ip_hash, p_user_agent_hash, 'Rate limited - account locked');
    
    RAISE EXCEPTION 'Account locked due to too many failed attempts. Try again later.';
  END IF;

  -- Get user record (FIXED: qualified column names)
  SELECT u.id, u.username, u.name, u.role_id, u.is_admin, u.is_active, u.preferred_lang, u.pin_hash
  INTO v_user_id, v_username, v_name, v_role_id, v_is_admin, v_is_active, v_language, v_pin_hash
  FROM public.users AS u
  WHERE lower(u.username) = v_username_lower;

  -- Check if user exists
  IF v_user_id IS NULL THEN
    -- Log failed attempt
    INSERT INTO public.login_audit (username, success, ip_hash, user_agent_hash, failure_reason)
    VALUES (v_username_lower, false, p_ip_hash, p_user_agent_hash, 'Invalid username');
    
    -- Update rate limiting
    INSERT INTO public.login_rate_limiting (username, ip_hash, attempt_count, first_attempt_at, last_attempt_at)
    VALUES (v_username_lower, p_ip_hash, 1, now(), now())
    ON CONFLICT (username, ip_hash) DO UPDATE
    SET attempt_count = public.login_rate_limiting.attempt_count + 1,
        last_attempt_at = now(),
        locked_until = CASE
          WHEN public.login_rate_limiting.attempt_count + 1 >= 5 THEN now() + interval '15 minutes'
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
    INSERT INTO public.login_audit (user_id, username, success, ip_hash, user_agent_hash, failure_reason)
    VALUES (v_user_id, v_username_lower, false, p_ip_hash, p_user_agent_hash, 'Invalid PIN');
    
    -- Update rate limiting (FIXED: qualified column names)
    INSERT INTO public.login_rate_limiting (username, ip_hash, attempt_count, first_attempt_at, last_attempt_at)
    VALUES (v_username_lower, p_ip_hash, 1, now(), now())
    ON CONFLICT (username, ip_hash) DO UPDATE
    SET attempt_count = public.login_rate_limiting.attempt_count + 1,
        last_attempt_at = now(),
        locked_until = CASE
          WHEN public.login_rate_limiting.attempt_count + 1 >= 5 THEN now() + interval '15 minutes'
          ELSE NULL
        END;
    
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

  -- Clear rate limiting
  DELETE FROM public.login_rate_limiting
  WHERE public.login_rate_limiting.username = v_username_lower AND public.login_rate_limiting.ip_hash = p_ip_hash;

  -- Return session info
  RETURN QUERY
  SELECT v_token, v_user_id, v_username, v_name, v_role_id, v_is_admin, v_is_active, v_language, v_expires_at;
END;
$$;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- Verify the function exists and has correct signature
-- ============================================================================

SELECT 
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS signature
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'verify_login';

-- Check tables exist
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' AND table_name IN ('login_audit', 'login_rate_limiting');

COMMIT;

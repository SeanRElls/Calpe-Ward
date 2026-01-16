-- ============================================================================
-- MASTER DEPLOYMENT: Complete Login & Auth System
-- ============================================================================
-- This file contains EVERYTHING needed for the new login system
-- Tables, functions, indexes, and audit logging
-- ============================================================================

BEGIN;

-- ============================================================================
-- PART 1: TABLES
-- ============================================================================

-- Add username column to users table
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS username text UNIQUE;

-- Backfill usernames
UPDATE public.users SET username = LOWER('user_' || SUBSTRING(id::text, 1, 8)) WHERE username IS NULL;

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

-- Add revoked_at column to sessions table if not present
ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS revoked_at timestamp with time zone;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_login_audit_user_id_login_at ON public.login_audit(user_id, login_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_audit_ip_hash_login_at ON public.login_audit(ip_hash, login_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_audit_success_login_at ON public.login_audit(success, login_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_rate_limiting_locked_until ON public.login_rate_limiting(locked_until);

-- ============================================================================
-- PART 2: LOGIN & SESSION FUNCTIONS
-- ============================================================================

-- 1. Standardized Login RPC with Rate Limiting
CREATE OR REPLACE FUNCTION public.verify_login(
  p_username text,
  p_pin text,
  p_ip_hash text DEFAULT 'unknown',
  p_user_agent_hash text DEFAULT 'unknown'
)
RETURNS TABLE(token uuid, user_id uuid, username text, error_message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user_id uuid;
  v_pin_hash text;
  v_username_lower text;
  v_token uuid;
  v_expires_at timestamp with time zone;
  v_error_msg text;
  v_locked_until timestamp with time zone;
BEGIN
  -- Normalize username
  v_username_lower := LOWER(TRIM(p_username));

  -- Check rate limiting FIRST
  SELECT locked_until INTO v_locked_until
  FROM public.login_rate_limiting
  WHERE username = v_username_lower AND ip_hash = p_ip_hash;

  IF v_locked_until IS NOT NULL AND v_locked_until > NOW() THEN
    v_error_msg := 'Account temporarily locked. Try again after ' || TO_CHAR(v_locked_until, 'HH24:MI') || ' UTC';
    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (NULL, v_username_lower, p_ip_hash, p_user_agent_hash, false, 'Rate limited (locked)');
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg::text;
    RETURN;
  END IF;

  -- Validate inputs
  IF v_username_lower IS NULL OR v_username_lower = '' THEN
    v_error_msg := 'Username is required';
    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (NULL, v_username_lower, p_ip_hash, p_user_agent_hash, false, v_error_msg);
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg::text;
    RETURN;
  END IF;

  IF p_pin IS NULL OR p_pin = '' OR LENGTH(p_pin) != 4 OR NOT p_pin ~ '^\d{4}$' THEN
    v_error_msg := 'PIN must be 4 digits';
    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (NULL, v_username_lower, p_ip_hash, p_user_agent_hash, false, v_error_msg);
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg::text;
    RETURN;
  END IF;

  -- Look up user
  SELECT id, pin_hash INTO v_user_id, v_pin_hash
  FROM public.users
  WHERE LOWER(username) = v_username_lower LIMIT 1;

  IF v_user_id IS NULL THEN
    v_error_msg := 'Invalid username or PIN';
    INSERT INTO public.login_rate_limiting (username, ip_hash, attempt_count)
    VALUES (v_username_lower, p_ip_hash, 1)
    ON CONFLICT(username, ip_hash) DO UPDATE
    SET attempt_count = login_rate_limiting.attempt_count + 1,
        last_attempt_at = NOW(),
        updated_at = NOW();
    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (NULL, v_username_lower, p_ip_hash, p_user_agent_hash, false, 'User not found');
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg::text;
    RETURN;
  END IF;

  -- Verify PIN
  IF v_pin_hash IS NULL OR v_pin_hash != public.crypt(p_pin, v_pin_hash) THEN
    v_error_msg := 'Invalid username or PIN';
    INSERT INTO public.login_rate_limiting (username, ip_hash, attempt_count)
    VALUES (v_username_lower, p_ip_hash, 1)
    ON CONFLICT(username, ip_hash) DO UPDATE
    SET attempt_count = login_rate_limiting.attempt_count + 1,
        last_attempt_at = NOW(),
        updated_at = NOW();
    
    UPDATE public.login_rate_limiting
    SET locked_until = NOW() + interval '15 minutes'
    WHERE username = v_username_lower AND ip_hash = p_ip_hash AND attempt_count >= 5;
    
    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (v_user_id, v_username_lower, p_ip_hash, p_user_agent_hash, false, 'Invalid PIN');
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg::text;
    RETURN;
  END IF;

  -- Check if user is active
  IF (SELECT is_active FROM public.users WHERE id = v_user_id) = false THEN
    v_error_msg := 'Account is inactive. Contact admin';
    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (v_user_id, v_username_lower, p_ip_hash, p_user_agent_hash, false, 'Account inactive');
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg::text;
    RETURN;
  END IF;

  -- SUCCESS: Create session and clear rate limiting
  v_token := gen_random_uuid();
  v_expires_at := NOW() + interval '8 hours';

  INSERT INTO public.sessions (token, user_id, expires_at)
  VALUES (v_token, v_user_id, v_expires_at);

  DELETE FROM public.login_rate_limiting
  WHERE username = v_username_lower AND ip_hash = p_ip_hash;

  INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success)
  VALUES (v_user_id, v_username_lower, p_ip_hash, p_user_agent_hash, true);

  RETURN QUERY SELECT v_token, v_user_id, v_username_lower, NULL::text;

EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, 'Login failed. Please try again'::text;
END;
$$;

-- 2. Session Validation RPC
CREATE OR REPLACE FUNCTION public.validate_session(p_token uuid)
RETURNS TABLE(valid boolean, user_id uuid, error_message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  SELECT user_id INTO v_user_id
  FROM public.sessions
  WHERE token = p_token
    AND expires_at > NOW()
    AND (revoked_at IS NULL OR revoked_at > NOW());

  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT false, NULL::uuid, 'Session expired or invalid'::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, v_user_id, NULL::text;

EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT false, NULL::uuid, 'Session validation failed'::text;
END;
$$;

-- 3. Session Revocation RPC
CREATE OR REPLACE FUNCTION public.revoke_session(p_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  UPDATE public.sessions
  SET revoked_at = NOW()
  WHERE token = p_token;
END;
$$;

-- 4. Cleanup expired rate limits
CREATE OR REPLACE FUNCTION public.cleanup_expired_rate_limits()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_deleted_count integer;
BEGIN
  DELETE FROM public.login_rate_limiting
  WHERE first_attempt_at < NOW() - interval '24 hours'
    AND (locked_until IS NULL OR locked_until < NOW());

  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  RETURN v_deleted_count;
END;
$$;

COMMIT;

-- ============================================================================
-- VERIFICATION QUERIES (run after deployment)
-- ============================================================================
-- SELECT 'login_audit table exists: ' || EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='login_audit' AND table_schema='public');
-- SELECT 'login_rate_limiting table exists: ' || EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='login_rate_limiting' AND table_schema='public');
-- SELECT 'users.username column exists: ' || EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='username');
-- SELECT 'sessions.revoked_at column exists: ' || EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='sessions' AND column_name='revoked_at');
-- SELECT COUNT(*) as users_with_username FROM public.users WHERE username IS NOT NULL;
-- SELECT proname FROM pg_proc WHERE proname IN ('verify_login', 'validate_session', 'revoke_session', 'cleanup_expired_rate_limits');

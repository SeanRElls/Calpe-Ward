-- ============================================================================
-- LOGIN AUTHENTICATION FUNCTION (Phase 3)
-- ============================================================================
-- Implements username + PIN login with session token generation
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Add username column to users table (if not exists)
-- ============================================================================

ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS username text UNIQUE;

-- ============================================================================
-- 2. Standardized Login RPC
-- ============================================================================

CREATE OR REPLACE FUNCTION public.verify_login(
  p_username text,
  p_pin text
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
BEGIN
  -- Normalize username (case-insensitive)
  v_username_lower := LOWER(TRIM(p_username));

  -- Validate inputs
  IF v_username_lower IS NULL OR v_username_lower = '' THEN
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, 'Username is required'::text;
    RETURN;
  END IF;

  IF p_pin IS NULL OR p_pin = '' OR LENGTH(p_pin) != 4 OR NOT p_pin ~ '^\d{4}$' THEN
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, 'PIN must be 4 digits'::text;
    RETURN;
  END IF;

  -- Look up user by username (case-insensitive)
  SELECT id, pin_hash INTO v_user_id, v_pin_hash
  FROM public.users
  WHERE LOWER(username) = v_username_lower
  LIMIT 1;

  IF v_user_id IS NULL THEN
    -- User not found - don't reveal this to client for security
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, 'Invalid username or PIN'::text;
    RETURN;
  END IF;

  -- Verify PIN
  IF v_pin_hash IS NULL OR v_pin_hash != public.crypt(p_pin, v_pin_hash) THEN
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, 'Invalid username or PIN'::text;
    RETURN;
  END IF;

  -- Check if user is active
  IF (SELECT is_active FROM public.users WHERE id = v_user_id) = false THEN
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, 'Account is inactive. Contact admin'::text;
    RETURN;
  END IF;

  -- Create session token
  v_token := gen_random_uuid();
  v_expires_at := NOW() + interval '8 hours';

  -- Insert session
  INSERT INTO public.sessions (token, user_id, expires_at)
  VALUES (v_token, v_user_id, v_expires_at);

  -- Return success with token
  RETURN QUERY SELECT v_token, v_user_id, v_username_lower, NULL::text;

EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, 'Login failed. Please try again'::text;
END;
$$;

-- ============================================================================
-- 3. Session Validation RPC
-- ============================================================================

CREATE OR REPLACE FUNCTION public.validate_session(p_token uuid)
RETURNS TABLE(valid boolean, user_id uuid, error_message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user_id uuid;
  v_is_revoked boolean;
BEGIN
  -- Check if token exists and is valid
  SELECT user_id 
  INTO v_user_id
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

-- ============================================================================
-- 4. Session Revocation RPC
-- ============================================================================

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

COMMIT;

-- ============================================================================
-- MIGRATION NOTES
-- ============================================================================
-- 
-- 1. Run this to backfill usernames from existing data (example):
--    UPDATE public.users SET username = 'user_' || id::text WHERE username IS NULL;
--
-- 2. After backfilling, add UNIQUE and NOT NULL constraints:
--    ALTER TABLE public.users ALTER COLUMN username SET NOT NULL;
--    
-- 3. Verify sessions table has revoked_at column:
--    ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS revoked_at timestamp with time zone;
--
-- ============================================================================

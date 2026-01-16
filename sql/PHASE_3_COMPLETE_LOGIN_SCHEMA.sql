-- ============================================================================
-- PHASE 3 COMPLETION: Login Schema Hardening
-- ============================================================================
-- Deploys missing requirements from login.readme Phase 1:
-- 1. sessions.revoked_at column
-- 2. login_audit table for audit logging
-- 3. login_rate_limiting table for rate limiting
-- 4. Support functions for audit and rate limiting
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Add revoked_at column to sessions table (if not already present)
-- ============================================================================

ALTER TABLE public.sessions
ADD COLUMN IF NOT EXISTS revoked_at timestamp with time zone;

-- ============================================================================
-- 2. Create login_audit table for security logging
-- ============================================================================
-- Records every login attempt (successful and failed)
-- Allows detection of brute force attacks and audit trail

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

-- Index for efficient queries by user_id and login_at
CREATE INDEX IF NOT EXISTS idx_login_audit_user_id_login_at 
  ON public.login_audit(user_id, login_at DESC);

-- Index for queries by ip_hash (for rate limiting)
CREATE INDEX IF NOT EXISTS idx_login_audit_ip_hash_login_at 
  ON public.login_audit(ip_hash, login_at DESC);

-- Index for queries by success status
CREATE INDEX IF NOT EXISTS idx_login_audit_success_login_at 
  ON public.login_audit(success, login_at DESC);

-- ============================================================================
-- 3. Create login_rate_limiting table
-- ============================================================================
-- Tracks login attempt counts by IP and username
-- Used to enforce rate limiting and lockout policies

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

-- Index for efficient lockout checks
CREATE INDEX IF NOT EXISTS idx_login_rate_limiting_locked_until 
  ON public.login_rate_limiting(locked_until);

-- ============================================================================
-- 4. Update verify_login to include audit logging
-- ============================================================================
-- Modified verify_login that logs all attempts and enforces rate limiting

CREATE OR REPLACE FUNCTION public.verify_login(
  p_username text,
  p_pin text,
  p_ip_hash text DEFAULT NULL,
  p_user_agent_hash text DEFAULT NULL
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
  v_ip_hash text;
  v_user_agent_hash text;
  v_is_locked boolean;
  v_locked_until timestamp with time zone;
  v_error_msg text;
BEGIN
  -- Set defaults for hashes (frontend should provide these, but allow NULL for backward compatibility)
  v_ip_hash := COALESCE(p_ip_hash, 'unknown');
  v_user_agent_hash := COALESCE(p_user_agent_hash, 'unknown');

  -- Normalize username (case-insensitive)
  v_username_lower := LOWER(TRIM(p_username));

  -- ========================================================================
  -- Check rate limiting FIRST (before any user lookup)
  -- ========================================================================
  SELECT locked_until INTO v_locked_until
  FROM public.login_rate_limiting
  WHERE username = v_username_lower
    AND ip_hash = v_ip_hash;

  IF v_locked_until IS NOT NULL AND v_locked_until > NOW() THEN
    v_error_msg := 'Account temporarily locked due to too many failed attempts. Try again after ' || 
                   TO_CHAR(v_locked_until, 'HH24:MI') || ' UTC';
    
    -- Log failed attempt
    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (NULL, v_username_lower, v_ip_hash, v_user_agent_hash, false, 'Rate limited (locked)');
    
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg::text;
    RETURN;
  END IF;

  -- ========================================================================
  -- Validate inputs
  -- ========================================================================
  IF v_username_lower IS NULL OR v_username_lower = '' THEN
    v_error_msg := 'Username is required';
    
    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (NULL, v_username_lower, v_ip_hash, v_user_agent_hash, false, v_error_msg);
    
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg::text;
    RETURN;
  END IF;

  IF p_pin IS NULL OR p_pin = '' OR LENGTH(p_pin) != 4 OR NOT p_pin ~ '^\d{4}$' THEN
    v_error_msg := 'PIN must be 4 digits';
    
    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (NULL, v_username_lower, v_ip_hash, v_user_agent_hash, false, v_error_msg);
    
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg::text;
    RETURN;
  END IF;

  -- ========================================================================
  -- Look up user by username
  -- ========================================================================
  SELECT id, pin_hash INTO v_user_id, v_pin_hash
  FROM public.users
  WHERE LOWER(username) = v_username_lower
  LIMIT 1;

  IF v_user_id IS NULL THEN
    v_error_msg := 'Invalid username or PIN';
    
    -- Update rate limiting (increment attempt count)
    INSERT INTO public.login_rate_limiting (username, ip_hash, attempt_count)
    VALUES (v_username_lower, v_ip_hash, 1)
    ON CONFLICT(username, ip_hash) DO UPDATE
    SET attempt_count = login_rate_limiting.attempt_count + 1,
        last_attempt_at = NOW(),
        updated_at = NOW();
    
    -- Log failed attempt
    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (NULL, v_username_lower, v_ip_hash, v_user_agent_hash, false, 'User not found');
    
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg::text;
    RETURN;
  END IF;

  -- ========================================================================
  -- Verify PIN
  -- ========================================================================
  IF v_pin_hash IS NULL OR v_pin_hash != public.crypt(p_pin, v_pin_hash) THEN
    v_error_msg := 'Invalid username or PIN';
    
    -- Update rate limiting (increment attempt count)
    INSERT INTO public.login_rate_limiting (username, ip_hash, attempt_count)
    VALUES (v_username_lower, v_ip_hash, 1)
    ON CONFLICT(username, ip_hash) DO UPDATE
    SET attempt_count = login_rate_limiting.attempt_count + 1,
        last_attempt_at = NOW(),
        updated_at = NOW();

    -- Lock account after 5 failed attempts
    UPDATE public.login_rate_limiting
    SET locked_until = NOW() + interval '15 minutes'
    WHERE username = v_username_lower
      AND ip_hash = v_ip_hash
      AND attempt_count >= 5;
    
    -- Log failed attempt
    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (v_user_id, v_username_lower, v_ip_hash, v_user_agent_hash, false, 'Invalid PIN');
    
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg::text;
    RETURN;
  END IF;

  -- ========================================================================
  -- Check if user is active
  -- ========================================================================
  IF (SELECT is_active FROM public.users WHERE id = v_user_id) = false THEN
    v_error_msg := 'Account is inactive. Contact admin';
    
    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (v_user_id, v_username_lower, v_ip_hash, v_user_agent_hash, false, 'Account inactive');
    
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg::text;
    RETURN;
  END IF;

  -- ========================================================================
  -- SUCCESS: Create session and clear rate limiting
  -- ========================================================================
  v_token := gen_random_uuid();
  v_expires_at := NOW() + interval '8 hours';

  -- Insert session
  INSERT INTO public.sessions (token, user_id, expires_at)
  VALUES (v_token, v_user_id, v_expires_at);

  -- Clear rate limiting on successful login
  DELETE FROM public.login_rate_limiting
  WHERE username = v_username_lower
    AND ip_hash = v_ip_hash;

  -- Log successful attempt
  INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success)
  VALUES (v_user_id, v_username_lower, v_ip_hash, v_user_agent_hash, true);

  -- Return success with token
  RETURN QUERY SELECT v_token, v_user_id, v_username_lower, NULL::text;

EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, 'Login failed. Please try again'::text;
END;
$$;

-- ============================================================================
-- 5. Create function to log audit events (for other operations)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.log_audit_event(
  p_username text,
  p_event_type text,
  p_event_description text,
  p_ip_hash text DEFAULT 'unknown',
  p_user_agent_hash text DEFAULT 'unknown'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  -- Look up user_id from username
  SELECT id INTO v_user_id
  FROM public.users
  WHERE LOWER(username) = LOWER(p_username)
  LIMIT 1;

  -- Log the event (insert into a hypothetical audit table)
  -- For now, we'll just log to login_audit as a generic event
  INSERT INTO public.login_audit (
    user_id, 
    username, 
    ip_hash, 
    user_agent_hash, 
    success
  )
  VALUES (
    v_user_id,
    p_username,
    p_ip_hash,
    p_user_agent_hash,
    true
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL; -- Silently fail audit logging to avoid disrupting main operations
END;
$$;

-- ============================================================================
-- 6. Create function to clear expired rate limits
-- ============================================================================

CREATE OR REPLACE FUNCTION public.cleanup_expired_rate_limits()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_deleted_count integer;
BEGIN
  -- Delete rate limit entries older than 24 hours with no active locks
  DELETE FROM public.login_rate_limiting
  WHERE first_attempt_at < NOW() - interval '24 hours'
    AND (locked_until IS NULL OR locked_until < NOW());

  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  RETURN v_deleted_count;
END;
$$;

-- ============================================================================
-- 7. Ensure users.username is NOT NULL for new records
-- ============================================================================

-- Note: Cannot use ALTER COLUMN SET NOT NULL if there are existing NULLs
-- First, backfill any NULL usernames:
UPDATE public.users 
SET username = 'user_' || SUBSTRING(id::text, 1, 8)
WHERE username IS NULL;

-- Then set NOT NULL constraint (if not already set):
-- ALTER TABLE public.users ALTER COLUMN username SET NOT NULL;

COMMIT;

-- ============================================================================
-- POST-DEPLOYMENT NOTES
-- ============================================================================
--
-- 1. Test rate limiting:
--    - Attempt 5 failed logins with same username + IP
--    - Should see locked_until timestamp set to NOW() + 15 minutes
--    - Further attempts should return "Account temporarily locked" message
--
-- 2. Verify audit logging:
--    SELECT * FROM login_audit ORDER BY login_at DESC LIMIT 10;
--
-- 3. Clean up old rate limiting entries periodically:
--    SELECT cleanup_expired_rate_limits();
--
-- 4. Monitor failed login patterns:
--    SELECT username, ip_hash, COUNT(*) as failed_attempts
--    FROM login_audit
--    WHERE success = false
--      AND login_at > NOW() - interval '1 hour'
--    GROUP BY username, ip_hash
--    ORDER BY failed_attempts DESC;
--
-- 5. Update frontend to pass p_ip_hash and p_user_agent_hash:
--    - Compute SHA256 hash of client IP (requires backend service or crypto library)
--    - Compute SHA256 hash of User-Agent header
--    - Pass both to verify_login() call
--
-- 6. If username column had NULLs, verify backfill completed:
--    SELECT COUNT(*) FROM users WHERE username IS NULL;
--    -- Should return 0
--
-- ============================================================================

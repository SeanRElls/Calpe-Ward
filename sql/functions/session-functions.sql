-- ============================================================================
-- ADD MISSING SESSION VALIDATION & REVOCATION FUNCTIONS
-- ============================================================================
-- These functions are required by session-validator.js
-- ============================================================================

BEGIN;

-- ============================================================================
-- CREATE VALIDATE_SESSION FUNCTION
-- ============================================================================
-- Validates if a token is active and not expired

DROP FUNCTION IF EXISTS public.validate_session(uuid);

CREATE OR REPLACE FUNCTION public.validate_session(p_token uuid)
RETURNS TABLE(valid boolean, user_id uuid, error_message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user_id uuid;
  v_expires_at timestamptz;
BEGIN
  -- Look up the session
  SELECT s.user_id, s.expires_at
  INTO v_user_id, v_expires_at
  FROM public.sessions AS s
  WHERE s.token = p_token;

  -- Check if session found and not expired
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT false, NULL::uuid, 'Session not found'::text;
    RETURN;
  END IF;

  IF v_expires_at < now() THEN
    RETURN QUERY SELECT false, NULL::uuid, 'Session expired'::text;
    RETURN;
  END IF;

  -- Session is valid
  RETURN QUERY SELECT true, v_user_id, NULL::text;
END;
$$;

-- ============================================================================
-- CREATE REVOKE_SESSION FUNCTION
-- ============================================================================
-- Revokes a session token

DROP FUNCTION IF EXISTS public.revoke_session(uuid);

CREATE OR REPLACE FUNCTION public.revoke_session(p_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- Mark session as revoked by setting expires_at to now
  UPDATE public.sessions
  SET expires_at = now()
  WHERE token = p_token;
END;
$$;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

SELECT 
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS signature
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN ('validate_session', 'revoke_session');

COMMIT;

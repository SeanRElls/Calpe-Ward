-- ============================================================================
-- CREATE REMAINING 5 TOKEN-ONLY FUNCTIONS
-- ============================================================================
-- Migrates the last 5 legacy functions to token-based authentication
-- ============================================================================

BEGIN;

-- ============================================================================
-- WEEK COMMENT FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_week_comments(p_token uuid, p_week_id uuid)
RETURNS TABLE(user_id uuid, comment text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
BEGIN
  -- Verify session and get user ID
  v_uid := public.require_session_permissions(p_token, null);

  RETURN QUERY
  SELECT wc.user_id, wc.comment
  FROM public.week_comments wc
  WHERE wc.week_id = p_week_id
  ORDER BY wc.user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_week_comment(
  p_token uuid,
  p_week_id uuid,
  p_user_id uuid,
  p_comment text
)
RETURNS TABLE(user_id uuid, week_id uuid, comment text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
  v_result RECORD;
BEGIN
  -- Verify session and get user ID
  v_uid := public.require_session_permissions(p_token, null);

  -- User can only edit their own comment (unless admin)
  IF v_uid != p_user_id THEN
    DECLARE
      v_is_admin boolean;
    BEGIN
      SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
      IF v_is_admin IS NULL OR NOT v_is_admin THEN
        RAISE EXCEPTION 'Cannot edit other users comments';
      END IF;
    END;
  END IF;

  -- Upsert the comment
  INSERT INTO public.week_comments (week_id, user_id, comment)
  VALUES (p_week_id, p_user_id, p_comment)
  ON CONFLICT (week_id, user_id) 
  DO UPDATE SET comment = p_comment
  RETURNING * INTO v_result;

  RETURN QUERY SELECT v_result.user_id, v_result.week_id, v_result.comment;
END;
$$;

-- ============================================================================
-- USER PREFERENCE FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.set_user_language(
  p_token uuid,
  p_lang text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
BEGIN
  -- Verify session and get user ID
  v_uid := public.require_session_permissions(p_token, null);

  -- Validate language
  IF p_lang NOT IN ('en', 'es') THEN
    RAISE EXCEPTION 'Invalid language. Must be en or es.';
  END IF;

  -- Update user's language preference
  UPDATE public.users
  SET preferred_lang = p_lang
  WHERE id = v_uid;

  RETURN p_lang;
END;
$$;

CREATE OR REPLACE FUNCTION public.change_user_pin(
  p_token uuid,
  p_old_pin text,
  p_new_pin text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
  v_stored_hash text;
BEGIN
  -- Verify session and get user ID
  v_uid := public.require_session_permissions(p_token, null);

  -- Get current pin hash
  SELECT pin_hash INTO v_stored_hash FROM public.users WHERE id = v_uid;

  -- Verify old PIN
  IF v_stored_hash IS NULL OR v_stored_hash != public.crypt(p_old_pin, v_stored_hash) THEN
    RAISE EXCEPTION 'Current PIN is incorrect';
  END IF;

  -- Update to new PIN
  UPDATE public.users
  SET pin_hash = public.crypt(p_new_pin, public.gen_salt('bf'))
  WHERE id = v_uid;
END;
$$;

-- ============================================================================
-- ADMIN USER PIN FUNCTION (already created in previous deployment)
-- ============================================================================
-- admin_set_user_pin already exists from DEPLOY_12_CRITICAL_FUNCTIONS.sql
-- No need to recreate

COMMIT;

-- ============================================================================
-- VERIFICATION QUERY
-- ============================================================================
-- Run this to confirm all 4 new functions were created successfully:
--
-- SELECT routine_name, routine_type
-- FROM information_schema.routines
-- WHERE routine_schema = 'public'
--   AND routine_name IN (
--     'get_week_comments',
--     'upsert_week_comment',
--     'set_user_language',
--     'change_user_pin'
--   )
-- ORDER BY routine_name;
-- 
-- Expected: 4 rows

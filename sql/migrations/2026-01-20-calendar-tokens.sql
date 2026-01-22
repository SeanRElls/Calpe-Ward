-- Calendar Subscription Tokens Migration
-- Creates secure token system for per-user ICS feed access
-- Last Updated: 2026-01-20

-- ============================================================================
-- CALENDAR TOKENS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.calendar_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz NULL,
  last_used_at timestamptz NULL,
  
  CONSTRAINT calendar_tokens_user_active_unique UNIQUE NULLS NOT DISTINCT (user_id, revoked_at)
);

CREATE INDEX idx_calendar_tokens_token_hash ON public.calendar_tokens(token_hash) 
  WHERE revoked_at IS NULL;

CREATE INDEX idx_calendar_tokens_user_id ON public.calendar_tokens(user_id) 
  WHERE revoked_at IS NULL;

COMMENT ON TABLE public.calendar_tokens IS 
  'Secure tokens for calendar feed access. Tokens are hashed (SHA-256) before storage.';
COMMENT ON COLUMN public.calendar_tokens.token_hash IS 
  'SHA-256 hash of the raw token (hex encoded). Never store raw tokens.';
COMMENT ON COLUMN public.calendar_tokens.revoked_at IS 
  'When token was revoked. NULL = active. Regenerating sets this timestamp.';
COMMENT ON COLUMN public.calendar_tokens.last_used_at IS 
  'Last time token was used to fetch calendar. Updated on each successful fetch.';

-- ============================================================================
-- RPC: GENERATE CALENDAR TOKEN
-- ============================================================================

CREATE OR REPLACE FUNCTION public.generate_calendar_token(
  p_token text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid;
  v_token_hash text;
  v_raw_token text;
  v_existing_id uuid;
BEGIN
  -- Authenticate and get user ID
  v_uid := public.require_session_permissions(p_token::uuid);
  
  -- Generate cryptographically secure random token (32 bytes = 64 hex chars)
  v_raw_token := encode(extensions.gen_random_bytes(32), 'hex');
  
  -- Hash the token for storage (SHA-256)
  v_token_hash := encode(extensions.digest(v_raw_token, 'sha256'), 'hex');
  
  -- Check if user already has an active token
  SELECT id INTO v_existing_id
  FROM public.calendar_tokens
  WHERE user_id = v_uid AND revoked_at IS NULL
  LIMIT 1;
  
  -- If exists, revoke it
  IF v_existing_id IS NOT NULL THEN
    UPDATE public.calendar_tokens
    SET revoked_at = now()
    WHERE id = v_existing_id;
  END IF;
  
  -- Insert new token
  INSERT INTO public.calendar_tokens (user_id, token_hash)
  VALUES (v_uid, v_token_hash);
  
  -- Return the raw token (only time it's ever visible)
  RETURN json_build_object(
    'success', true,
    'token', v_raw_token,
    'message', 'Calendar token generated. Save this token - it will not be shown again.'
  );
END;
$$;

COMMENT ON FUNCTION public.generate_calendar_token(text) IS
  'Generate a new calendar subscription token for the authenticated user. Revokes any existing active token.';

-- ============================================================================
-- RPC: REVOKE CALENDAR TOKEN
-- ============================================================================

CREATE OR REPLACE FUNCTION public.revoke_calendar_token(
  p_token text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid;
  v_revoked_count int;
BEGIN
  -- Authenticate and get user ID
  v_uid := public.require_session_permissions(p_token::uuid);
  
  -- Revoke all active tokens for this user
  UPDATE public.calendar_tokens
  SET revoked_at = now()
  WHERE user_id = v_uid AND revoked_at IS NULL;
  
  GET DIAGNOSTICS v_revoked_count = ROW_COUNT;
  
  RETURN json_build_object(
    'success', true,
    'revoked_count', v_revoked_count,
    'message', 'Calendar token revoked'
  );
END;
$$;

COMMENT ON FUNCTION public.revoke_calendar_token(text) IS
  'Revoke the user''s active calendar token. They will need to generate a new one.';

-- ============================================================================
-- RPC: GET PUBLISHED SHIFTS FOR CALENDAR
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_published_shifts_for_calendar(
  p_calendar_token text
)
RETURNS TABLE(
  assignment_id bigint,
  shift_date date,
  shift_code text,
  shift_label text,
  start_time time,
  end_time time,
  hours_value numeric,
  comments text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token_hash text;
  v_user_id uuid;
  v_is_admin boolean;
  v_token_record record;
BEGIN
  -- Hash the incoming token
  v_token_hash := encode(extensions.digest(p_calendar_token, 'sha256'), 'hex');
  
  -- Look up token and validate
  SELECT ct.user_id, ct.id INTO v_token_record
  FROM public.calendar_tokens ct
  WHERE ct.token_hash = v_token_hash
    AND ct.revoked_at IS NULL
  LIMIT 1;
  
  -- Token not found or revoked
  IF v_token_record IS NULL THEN
    RAISE EXCEPTION 'Invalid or revoked calendar token'
      USING HINT = 'Token not found or has been revoked';
  END IF;
  
  v_user_id := v_token_record.user_id;
  
  -- Check if user is admin
  SELECT u.is_admin INTO v_is_admin FROM public.users u WHERE u.id = v_user_id;
  IF v_is_admin IS NULL THEN
    v_is_admin := false;
  END IF;
  
  -- Update last_used_at (fire and forget, don't fail if this errors)
  BEGIN
    UPDATE public.calendar_tokens
    SET last_used_at = now()
    WHERE id = v_token_record.id;
  EXCEPTION WHEN OTHERS THEN
    -- Ignore errors updating last_used_at
    NULL;
  END;
  
  -- Return published shifts for this user with appropriate comments
  -- Include past 30 days and all future shifts
  -- Admins see all comments; regular staff see only non-admin-only comments
  RETURN QUERY
  SELECT 
    ra.id::bigint AS assignment_id,
    ra.date AS shift_date,
    s.code AS shift_code,
    s.label AS shift_label,
    s.start_time,
    s.end_time,
    s.hours_value,
    -- Aggregate comments: filter by is_admin_only based on user role
    string_agg(
      rac.comment, 
      E'\n' 
      ORDER BY rac.created_at
    ) FILTER (
      WHERE (rac.is_admin_only = false OR v_is_admin)
    )::text AS comments
  FROM public.rota_assignments ra
  JOIN public.shifts s ON s.id = ra.shift_id
  LEFT JOIN public.rota_assignment_comments rac ON rac.rota_assignment_id = ra.id
  WHERE ra.user_id = v_user_id
    AND ra.status = 'published'
    AND ra.date >= CURRENT_DATE - interval '30 days'
  GROUP BY ra.id, s.id, ra.date, s.code, s.label, s.start_time, s.end_time, s.hours_value
  ORDER BY ra.date, s.start_time;
END;
$$;

COMMENT ON FUNCTION public.get_published_shifts_for_calendar(text) IS
  'Fetch published shifts for calendar feed. Validates token, returns shift details with catalogue labels. Includes past 30 days + all future.';

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT SELECT ON public.calendar_tokens TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_calendar_token(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_calendar_token(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_published_shifts_for_calendar(text) TO anon;

-- ============================================================================
-- RLS POLICIES (calendar_tokens table)
-- ============================================================================

ALTER TABLE public.calendar_tokens ENABLE ROW LEVEL SECURITY;

-- Users can only see their own tokens
CREATE POLICY calendar_tokens_user_read ON public.calendar_tokens
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- No direct INSERT/UPDATE/DELETE - must use RPCs
CREATE POLICY calendar_tokens_no_direct_write ON public.calendar_tokens
  FOR ALL
  TO authenticated
  USING (false);

COMMENT ON POLICY calendar_tokens_user_read ON public.calendar_tokens IS
  'Users can view their own calendar tokens';
COMMENT ON POLICY calendar_tokens_no_direct_write ON public.calendar_tokens IS
  'Prevent direct table access - must use RPCs for token management';

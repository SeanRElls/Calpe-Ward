-- ============================================================================
-- COMPLETE CALPE WARD SECURITY UPGRADE - FINAL DEPLOYMENT
-- ============================================================================
-- This file contains EVERYTHING deployed during the security upgrade:
-- 1. Login & Session Authentication System
-- 2. Audit Logging & Rate Limiting
-- 3. 12 Critical Token-Only Admin/Swap Functions
-- 4. 4 Additional Token-Only User Functions
-- 5. Session Permissions Helper
-- 6. All Required Tables & Indexes
-- ============================================================================

BEGIN;

-- ============================================================================
-- PART 1: SCHEMA & TABLES
-- ============================================================================

-- Add username column to users table
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS username text UNIQUE;

-- Backfill usernames
UPDATE public.users SET username = LOWER('user_' || SUBSTRING(id::text, 1, 8)) WHERE username IS NULL;

-- Create login_audit table
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

-- Create login_rate_limiting table
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

-- Add revoked_at column to sessions table
ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS revoked_at timestamp with time zone;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_login_audit_user_id_login_at ON public.login_audit(user_id, login_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_audit_ip_hash_login_at ON public.login_audit(ip_hash, login_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_audit_success_login_at ON public.login_audit(success, login_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_rate_limiting_locked_until ON public.login_rate_limiting(locked_until);

-- ============================================================================
-- PART 2: SESSION & PERMISSION FUNCTIONS
-- ============================================================================

-- Drop existing require_session_permissions if it exists to avoid conflicts
DROP FUNCTION IF EXISTS public.require_session_permissions(uuid, text[]);

-- Session Permissions Helper - Used by all token-based functions
CREATE OR REPLACE FUNCTION public.require_session_permissions(
  p_token uuid,
  p_required_permissions text[] DEFAULT NULL::text[]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user_id uuid;
  v_is_admin boolean;
  v_permission text;
  v_has_permission boolean;
BEGIN
  -- Verify session exists and is valid
  SELECT user_id INTO v_user_id
  FROM public.sessions
  WHERE token = p_token
    AND expires_at > NOW()
    AND (revoked_at IS NULL OR revoked_at > NOW());

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired session token';
  END IF;

  -- If no permissions required, just return user_id
  IF p_required_permissions IS NULL OR array_length(p_required_permissions, 1) IS NULL THEN
    RETURN v_user_id;
  END IF;

  -- Check if user is admin
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_user_id;
  
  -- Admins have all permissions
  IF v_is_admin THEN
    RETURN v_user_id;
  END IF;

  -- Check if user has any of the required permissions
  FOREACH v_permission IN ARRAY p_required_permissions
  LOOP
    SELECT EXISTS(
      SELECT 1 FROM public.user_permission_groups upg
      JOIN public.permission_group_permissions pgp ON upg.permission_group_id = pgp.permission_group_id
      JOIN public.permissions p ON pgp.permission_id = p.id
      WHERE upg.user_id = v_user_id AND p.name = v_permission
    ) INTO v_has_permission;
    
    IF v_has_permission THEN
      RETURN v_user_id;
    END IF;
  END LOOP;

  RAISE EXCEPTION 'Insufficient permissions for operation';
END;
$$;

-- Login RPC with Rate Limiting
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
  SELECT lrl.locked_until INTO v_locked_until
  FROM public.login_rate_limiting lrl
  WHERE lrl.username = v_username_lower AND lrl.ip_hash = p_ip_hash;

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
    SET attempt_count = public.login_rate_limiting.attempt_count + 1,
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
    SET attempt_count = public.login_rate_limiting.attempt_count + 1,
      last_attempt_at = NOW(),
      updated_at = NOW();
    
    UPDATE public.login_rate_limiting lrl
    SET locked_until = NOW() + interval '15 minutes'
    WHERE lrl.username = v_username_lower AND lrl.ip_hash = p_ip_hash AND lrl.attempt_count >= 5;
    
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
    -- Return the server-side error to aid diagnosis
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, ('Login failed: ' || SQLERRM)::text;
END;
$$;

-- Session Validation RPC
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

-- Session Revocation RPC
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

-- Cleanup expired rate limits
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

-- ============================================================================
-- PART 3: 12 CRITICAL TOKEN-ONLY ADMIN & SWAP FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_execute_shift_swap(
  p_token uuid,
  p_initiator_user_id uuid,
  p_initiator_shift_date date,
  p_counterparty_user_id uuid,
  p_counterparty_shift_date date,
  p_period_id integer DEFAULT NULL::integer
)
RETURNS TABLE(success boolean, swap_execution_id uuid, error_message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
  v_swap_exec_id uuid;
  v_initiator_shift_id bigint;
  v_counterparty_shift_id bigint;
  v_period_id_to_use integer;
  v_initiator_old_shift_id bigint;
  v_counterparty_old_shift_id bigint;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['manage_shifts']);
  END IF;

  IF p_period_id IS NOT NULL THEN
    v_period_id_to_use := p_period_id;
  ELSE
    SELECT id INTO v_period_id_to_use FROM public.rota_periods WHERE is_active = true;
  END IF;

  IF v_period_id_to_use IS NULL THEN
    RETURN QUERY SELECT false, null::uuid, 'no_active_period'::text;
    RETURN;
  END IF;

  SELECT id INTO v_initiator_shift_id
  FROM public.rota_assignments
  WHERE user_id = p_initiator_user_id AND date = p_initiator_shift_date AND status = 'published'
  LIMIT 1;

  IF v_initiator_shift_id IS NULL THEN
    RETURN QUERY SELECT false, null::uuid, 'initiator_shift_not_found'::text;
    RETURN;
  END IF;

  SELECT id INTO v_counterparty_shift_id
  FROM public.rota_assignments
  WHERE user_id = p_counterparty_user_id AND date = p_counterparty_shift_date AND status = 'published'
  LIMIT 1;

  IF v_counterparty_shift_id IS NULL THEN
    RETURN QUERY SELECT false, null::uuid, 'counterparty_shift_not_found'::text;
    RETURN;
  END IF;

  SELECT shift_id INTO v_initiator_old_shift_id FROM public.rota_assignments WHERE id = v_initiator_shift_id;
  SELECT shift_id INTO v_counterparty_old_shift_id FROM public.rota_assignments WHERE id = v_counterparty_shift_id;

  UPDATE public.rota_assignments SET shift_id = v_counterparty_old_shift_id WHERE id = v_initiator_shift_id;
  UPDATE public.rota_assignments SET shift_id = v_initiator_old_shift_id WHERE id = v_counterparty_shift_id;

  v_swap_exec_id := gen_random_uuid();
  INSERT INTO public.swap_executions (
    id, period_id, initiator_user_id, initiator_shift_date, counterparty_user_id,
    counterparty_shift_date, authoriser_user_id, method
  ) VALUES (
    v_swap_exec_id, v_period_id_to_use, p_initiator_user_id, p_initiator_shift_date,
    p_counterparty_user_id, p_counterparty_shift_date, v_admin_uid, 'admin_direct'
  );

  RETURN QUERY SELECT true, v_swap_exec_id, null::text;
EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT false, null::uuid, SQLERRM::text;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_upsert_notice(
  p_token uuid,
  p_notice_id uuid,
  p_title text,
  p_body_en text,
  p_body_es text,
  p_target_all boolean,
  p_target_roles integer[]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
  v_id uuid;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    IF p_notice_id IS NULL THEN
      PERFORM public.require_session_permissions(p_token, ARRAY['notices.create']);
    ELSE
      PERFORM public.require_session_permissions(p_token, ARRAY['notices.edit']);
    END IF;
  END IF;

  IF p_notice_id IS NULL THEN
    v_id := gen_random_uuid();
    INSERT INTO public.notices (id, title, body_en, body_es, target_all, created_by, is_active)
    VALUES (v_id, p_title, p_body_en, p_body_es, p_target_all, v_admin_uid, true);
  ELSE
    v_id := p_notice_id;
    UPDATE public.notices SET title = p_title, body_en = p_body_en, body_es = p_body_es, target_all = p_target_all WHERE id = v_id;
  END IF;

  DELETE FROM public.notice_targets WHERE notice_id = v_id;
  INSERT INTO public.notice_targets (notice_id, role_id) SELECT v_id, UNNEST(p_target_roles);

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_notice_ack_counts(p_token uuid, p_notice_ids uuid[])
RETURNS TABLE(notice_id uuid, acked_count bigint, pending_count bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['notices.view_ack_lists']);
  END IF;

  RETURN QUERY
  SELECT n.id AS notice_id, COUNT(na.user_id) AS acked_count,
         (SELECT COUNT(*) FROM public.users WHERE is_active = true) - COUNT(na.user_id) AS pending_count
  FROM UNNEST(p_notice_ids) AS n(id)
  LEFT JOIN public.notice_ack na ON na.notice_id = n.id
  GROUP BY n.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_period_closes_at(p_token uuid, p_period_id uuid, p_closes_at timestamp with time zone)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['periods.set_close_time']);
  END IF;
  UPDATE public.rota_periods SET closes_at = p_closes_at WHERE id = p_period_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_create_five_week_period(
  p_token uuid,
  p_name text,
  p_start_date date,
  p_end_date date
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
  v_period_id uuid;
  v_week_id uuid;
  v_week_start date;
  v_week_end date;
  v_current_date date;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['periods.create']);
  END IF;

  v_period_id := gen_random_uuid();
  INSERT INTO public.rota_periods (id, name, start, "end", is_active, is_hidden)
  VALUES (v_period_id, p_name, p_start_date, p_end_date, false, false);

  v_week_start := p_start_date;
  FOR i IN 1..5 LOOP
    v_week_end := v_week_start + interval '6 days';
    IF v_week_end > p_end_date THEN v_week_end := p_end_date; END IF;

    v_week_id := gen_random_uuid();
    INSERT INTO public.rota_weeks (id, period_id, week_number, start, "end", is_open, is_open_after_close)
    VALUES (v_week_id, v_period_id, i, v_week_start, v_week_end, false, false);

    v_current_date := v_week_start;
    WHILE v_current_date <= v_week_end LOOP
      INSERT INTO public.rota_dates (week_id, date) VALUES (v_week_id, v_current_date);
      v_current_date := v_current_date + interval '1 day';
    END LOOP;

    v_week_start := v_week_end + interval '1 day';
  END LOOP;

  RETURN v_period_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_request_cell(
  p_token uuid,
  p_target_user_id uuid,
  p_date date,
  p_value text,
  p_important_rank smallint DEFAULT NULL::smallint
)
RETURNS TABLE(out_id uuid, out_user_id uuid, out_date date, out_value text, out_important_rank smallint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
  v_request public.requests;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['requests.edit_all']);
  END IF;

  INSERT INTO public.requests (id, user_id, date, value, important_rank)
  VALUES (gen_random_uuid(), p_target_user_id, p_date, p_value, p_important_rank)
  ON CONFLICT (user_id, date) DO UPDATE
  SET value = p_value, important_rank = COALESCE(p_important_rank, EXCLUDED.important_rank)
  RETURNING * INTO v_request;

  RETURN QUERY SELECT v_request.id, v_request.user_id, v_request.date, v_request.value, v_request.important_rank;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_clear_request_cell(p_token uuid, p_target_user_id uuid, p_date date)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['requests.edit_all']);
  END IF;
  DELETE FROM public.requests WHERE user_id = p_target_user_id AND date = p_date;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_lock_request_cell(
  p_token uuid,
  p_target_user_id uuid,
  p_date date,
  p_reason_en text DEFAULT NULL::text,
  p_reason_es text DEFAULT NULL::text
)
RETURNS public.request_cell_locks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
  row public.request_cell_locks;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['requests.lock_cells']);
  END IF;

  INSERT INTO public.request_cell_locks (user_id, date, reason_en, reason_es)
  VALUES (p_target_user_id, p_date, p_reason_en, p_reason_es)
  ON CONFLICT (user_id, date) DO UPDATE
  SET reason_en = p_reason_en, reason_es = p_reason_es
  RETURNING * INTO row;

  RETURN row;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_unlock_request_cell(p_token uuid, p_target_user_id uuid, p_date date)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['requests.lock_cells']);
  END IF;
  DELETE FROM public.request_cell_locks WHERE user_id = p_target_user_id AND date = p_date;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_week_open_flags(
  p_token uuid,
  p_week_id uuid,
  p_open boolean,
  p_open_after_close boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['weeks.set_open_flags']);
  END IF;
  UPDATE public.rota_weeks SET is_open = p_open, is_open_after_close = p_open_after_close WHERE id = p_week_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_upsert_user(p_token uuid, p_user_id uuid, p_name text, p_role_id integer)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
  v_id uuid;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    IF p_user_id IS NULL THEN
      PERFORM public.require_session_permissions(p_token, ARRAY['users.create']);
    ELSE
      PERFORM public.require_session_permissions(p_token, ARRAY['users.edit']);
    END IF;
  END IF;

  IF p_user_id IS NULL THEN
    v_id := gen_random_uuid();
    INSERT INTO public.users (id, name, role_id, is_active) VALUES (v_id, p_name, p_role_id, true);
  ELSE
    v_id := p_user_id;
    UPDATE public.users SET name = p_name, role_id = p_role_id WHERE id = v_id;
  END IF;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_user_active(p_token uuid, p_user_id uuid, p_active boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['users.toggle_active']);
  END IF;
  UPDATE public.users SET is_active = p_active WHERE id = p_user_id;
END;
$$;

-- ============================================================================
-- PART 4: 4 ADDITIONAL TOKEN-ONLY USER FUNCTIONS
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
  v_uid := public.require_session_permissions(p_token, null);
  RETURN QUERY SELECT wc.user_id, wc.comment FROM public.week_comments wc WHERE wc.week_id = p_week_id ORDER BY wc.user_id;
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
  v_uid := public.require_session_permissions(p_token, null);

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

  INSERT INTO public.week_comments (week_id, user_id, comment)
  VALUES (p_week_id, p_user_id, p_comment)
  ON CONFLICT (week_id, user_id) DO UPDATE SET comment = p_comment
  RETURNING * INTO v_result;

  RETURN QUERY SELECT v_result.user_id, v_result.week_id, v_result.comment;
END;
$$;

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
  v_uid := public.require_session_permissions(p_token, null);

  IF p_lang NOT IN ('en', 'es') THEN
    RAISE EXCEPTION 'Invalid language. Must be en or es.';
  END IF;

  UPDATE public.users SET preferred_lang = p_lang WHERE id = v_uid;
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
  v_uid := public.require_session_permissions(p_token, null);
  SELECT pin_hash INTO v_stored_hash FROM public.users WHERE id = v_uid;

  IF v_stored_hash IS NULL OR v_stored_hash != public.crypt(p_old_pin, v_stored_hash) THEN
    RAISE EXCEPTION 'Current PIN is incorrect';
  END IF;

  UPDATE public.users SET pin_hash = public.crypt(p_new_pin, public.gen_salt('bf')) WHERE id = v_uid;
END;
$$;

COMMIT;

-- ============================================================================
-- FINAL VERIFICATION QUERIES
-- ============================================================================
-- Run these to confirm everything deployed successfully:
--
-- Check tables:
-- SELECT 'login_audit' as table_name FROM information_schema.tables WHERE table_name='login_audit' AND table_schema='public'
-- UNION ALL SELECT 'login_rate_limiting' FROM information_schema.tables WHERE table_name='login_rate_limiting' AND table_schema='public';
--
-- Check columns:
-- SELECT 'username' as column_name FROM information_schema.columns WHERE table_name='users' AND column_name='username'
-- UNION ALL SELECT 'revoked_at' FROM information_schema.columns WHERE table_name='sessions' AND column_name='revoked_at';
--
-- Check functions:
-- SELECT proname FROM pg_proc WHERE proname IN (
--   'verify_login', 'validate_session', 'revoke_session', 'cleanup_expired_rate_limits', 'require_session_permissions',
--   'admin_execute_shift_swap', 'admin_upsert_notice', 'admin_notice_ack_counts', 'admin_set_period_closes_at',
--   'admin_create_five_week_period', 'admin_set_request_cell', 'admin_clear_request_cell', 'admin_lock_request_cell',
--   'admin_unlock_request_cell', 'admin_set_week_open_flags', 'admin_upsert_user', 'set_user_active',
--   'get_week_comments', 'upsert_week_comment', 'set_user_language', 'change_user_pin'
-- ) ORDER BY proname;
-- Expected: 21 functions
-- ============================================================================

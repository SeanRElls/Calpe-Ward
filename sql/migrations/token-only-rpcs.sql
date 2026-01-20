-- ============================================================================
-- MIGRATION: Harden all RPCs to token-only (staff) + is_admin bypass (admin)
-- ============================================================================
-- Date: 2026-01-16
-- Goal: No more p_user_id/p_pin in staff/admin RPCs. Token-based auth only.
--       Staff functions infer user from token. Admin functions use is_admin bypass.
--       All SECURITY DEFINER functions set search_path safely.
-- ============================================================================

BEGIN;

-- ============================================================================
-- PHASE 1: Drop old overloads (staff RPCs with p_user_id/p_pin)
-- ============================================================================

-- ack_notice: drop (p_token, p_notice_id, p_user_id, p_version) overload
DROP FUNCTION IF EXISTS public.ack_notice(uuid, uuid, uuid, integer);

-- acknowledge_notice: drop (p_token, p_user_id, p_notice_id) overload
DROP FUNCTION IF EXISTS public.acknowledge_notice(uuid, uuid, uuid);

-- clear_request_cell: drop (p_token, p_user_id, p_date) overload
DROP FUNCTION IF EXISTS public.clear_request_cell(uuid, uuid, date);

-- get_all_notices: drop (p_token, p_user_id) overload
DROP FUNCTION IF EXISTS public.get_all_notices(uuid, uuid);

-- get_notices_for_user: drop (p_token, p_user_id) overload
DROP FUNCTION IF EXISTS public.get_notices_for_user(uuid, uuid);

-- get_pending_swap_requests_for_me: drop old versions (with p_user_id or p_token, p_user_id)
DROP FUNCTION IF EXISTS public.get_pending_swap_requests_for_me(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_pending_swap_requests_for_me(uuid);

-- set_request_cell: drop (p_token, p_user_id, p_date, p_value, p_important_rank) overload
DROP FUNCTION IF EXISTS public.set_request_cell(uuid, uuid, date, text, smallint);

-- staff_request_shift_swap: drop old overloads (with p_user_id, integer period_id, or uuid period_id)
DROP FUNCTION IF EXISTS public.staff_request_shift_swap(uuid, uuid, date, uuid, date, integer);
DROP FUNCTION IF EXISTS public.staff_request_shift_swap(uuid, date, uuid, date, integer);
DROP FUNCTION IF EXISTS public.staff_request_shift_swap(uuid, date, uuid, date, uuid);

-- staff_respond_to_swap_request: drop (p_token, p_user_id, p_swap_request_id, p_response) overload
DROP FUNCTION IF EXISTS public.staff_respond_to_swap_request(uuid, uuid, uuid, text);

-- admin_set_user_active: drop prior version to allow parameter rename
DROP FUNCTION IF EXISTS public.admin_set_user_active(uuid, uuid, boolean);

-- admin_set_user_pin: drop prior version to allow parameter rename
DROP FUNCTION IF EXISTS public.admin_set_user_pin(uuid, uuid, text);

-- admin_execute_shift_swap: drop prior overloads to avoid ambiguity
DROP FUNCTION IF EXISTS public.admin_execute_shift_swap(uuid, uuid, date, uuid, date, integer);

-- admin_get_swap_requests: drop prior version with integer period_id
DROP FUNCTION IF EXISTS public.admin_get_swap_requests(uuid);

-- admin_get_swap_executions: drop prior version with integer period_id
DROP FUNCTION IF EXISTS public.admin_get_swap_executions(uuid, integer);

-- ============================================================================
-- PHASE 2: Recreate staff RPCs as token-only
-- ============================================================================

-- Get unread notices (existing, but ensure signature is correct)
-- This may already exist, so using CREATE OR REPLACE
CREATE OR REPLACE FUNCTION public.get_unread_notices(p_token uuid)
RETURNS TABLE(
  id uuid,
  created_at timestamp with time zone,
  updated_at timestamp with time zone,
  title text,
  body_en text,
  body_es text,
  target_role_id integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
  v_user public.users;
BEGIN
  v_uid := public.require_session_permissions(p_token, null);

  SELECT * INTO v_user FROM public.users WHERE id = v_uid;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'permission_denied: user not found';
  END IF;

  RETURN QUERY
  SELECT DISTINCT
    n.id,
    n.created_at,
    n.updated_at,
    n.title,
    n.body_en,
    n.body_es,
    n.target_role_id
  FROM public.notices n
  LEFT JOIN public.notice_ack na ON na.notice_id = n.id AND na.user_id = v_uid
  WHERE n.is_active = true
    AND (n.target_all = true OR n.target_role_id = v_user.role_id)
    AND na.notice_id IS NULL
  ORDER BY n.created_at DESC;
END;
$$;

-- Get all notices (token-only)
CREATE OR REPLACE FUNCTION public.get_all_notices(p_token uuid)
RETURNS TABLE(
  id uuid,
  created_at timestamp with time zone,
  updated_at timestamp with time zone,
  title text,
  body_en text,
  body_es text,
  target_role_id integer,
  acknowledged boolean,
  acknowledged_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
  v_user public.users;
BEGIN
  v_uid := public.require_session_permissions(p_token, null);

  SELECT * INTO v_user FROM public.users WHERE id = v_uid;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'permission_denied: user not found';
  END IF;

  RETURN QUERY
  SELECT
    n.id,
    n.created_at,
    n.updated_at,
    n.title,
    n.body_en,
    n.body_es,
    n.target_role_id,
    COALESCE(na.notice_id IS NOT NULL, false) as acknowledged,
    na.acknowledged_at
  FROM public.notices n
  LEFT JOIN public.notice_ack na ON na.notice_id = n.id AND na.user_id = v_uid
  WHERE n.is_active = true
    AND (n.target_all = true OR n.target_role_id = v_user.role_id)
  ORDER BY n.created_at DESC;
END;
$$;

-- Get notices for user (token-only)
CREATE OR REPLACE FUNCTION public.get_notices_for_user(p_token uuid)
RETURNS TABLE(
  id uuid,
  title text,
  body_en text,
  body_es text,
  version integer,
  is_active boolean,
  updated_at timestamp with time zone,
  created_by uuid,
  created_by_name text,
  target_all boolean,
  target_roles integer[],
  acknowledged_at timestamp with time zone,
  ack_version integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
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
  FROM notices n
  LEFT JOIN users u ON u.id = n.created_by
  LEFT JOIN notice_targets nt ON nt.notice_id = n.id
  LEFT JOIN notice_ack na ON na.notice_id = n.id
    AND na.user_id = (SELECT user_id FROM sessions WHERE token = p_token AND expires_at > now() AND revoked_at IS NULL)
  WHERE n.is_active = true
  GROUP BY n.id, u.id, na.user_id, na.acknowledged_at, na.version
  ORDER BY n.updated_at DESC;
$$;

-- Acknowledge notice (token-only)
CREATE OR REPLACE FUNCTION public.acknowledge_notice(p_token uuid, p_notice_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := public.require_session_permissions(p_token, null);

  INSERT INTO public.notice_ack (notice_id, user_id, acknowledged_at)
  VALUES (p_notice_id, v_uid, now())
  ON CONFLICT (notice_id, user_id) DO UPDATE
  SET acknowledged_at = now();
END;
$$;

-- Ack notice with version (token-only)
CREATE OR REPLACE FUNCTION public.ack_notice(p_token uuid, p_notice_id uuid, p_version integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := public.require_session_permissions(p_token, null);

  INSERT INTO public.notice_ack (notice_id, user_id, acknowledged_at, version)
  VALUES (p_notice_id, v_uid, now(), p_version)
  ON CONFLICT (notice_id, user_id) DO UPDATE
  SET acknowledged_at = now(), version = p_version;
END;
$$;

-- Set request cell (token-only)
CREATE OR REPLACE FUNCTION public.set_request_cell(p_token uuid, p_date date, p_value text, p_important_rank smallint DEFAULT NULL::smallint)
RETURNS TABLE(
  out_id uuid,
  out_user_id uuid,
  out_date date,
  out_value text,
  out_important_rank smallint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
  v_period_id uuid;
  v_week_start date;
  v_week_end date;
  v_request public.requests;
BEGIN
  v_uid := public.require_session_permissions(p_token, null);

  -- Find active period
  SELECT id INTO v_period_id FROM public.rota_periods WHERE is_active = true;
  IF v_period_id IS NULL THEN
    RAISE EXCEPTION 'no_active_period';
  END IF;

  -- Find week containing the date
  SELECT week_start, week_end INTO v_week_start, v_week_end
  FROM public.rota_weeks
  WHERE period_id = v_period_id
    AND week_start <= p_date AND p_date <= week_end;

  IF v_week_start IS NULL THEN
    RAISE EXCEPTION 'date_not_in_period';
  END IF;

  -- Upsert request
  INSERT INTO public.requests (id, user_id, date, value, important_rank)
  VALUES (gen_random_uuid(), v_uid, p_date, p_value, p_important_rank)
  ON CONFLICT (user_id, date) DO UPDATE
  SET value = p_value, important_rank = COALESCE(p_important_rank, EXCLUDED.important_rank)
  RETURNING * INTO v_request;

  RETURN QUERY SELECT v_request.id, v_request.user_id, v_request.date, v_request.value, v_request.important_rank;
END;
$$;

-- Clear request cell (token-only)
CREATE OR REPLACE FUNCTION public.clear_request_cell(p_token uuid, p_date date)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := public.require_session_permissions(p_token, null);

  DELETE FROM public.requests
  WHERE user_id = v_uid AND date = p_date;
END;
$$;

-- Save request with pin (token-only, renamed function but keeping the name for compatibility)
CREATE OR REPLACE FUNCTION public.save_request_with_pin(p_token uuid, p_date date, p_value text, p_important_rank integer)
RETURNS public.requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
  r public.requests;
BEGIN
  v_uid := public.require_session_permissions(p_token, null);

  INSERT INTO public.requests (id, user_id, date, value, important_rank)
  VALUES (gen_random_uuid(), v_uid, p_date, p_value, p_important_rank)
  ON CONFLICT (user_id, date) DO NOTHING
  RETURNING * INTO r;

  -- If it was a conflict, fetch the existing row
  IF r IS NULL THEN
    SELECT * INTO r FROM public.requests WHERE user_id = v_uid AND date = p_date;
  END IF;

  RETURN r;
END;
$$;

-- Upsert request with pin (token-only, renamed function but keeping the name for compatibility)
CREATE OR REPLACE FUNCTION public.upsert_request_with_pin(p_token uuid, p_date date, p_value text, p_important_rank integer DEFAULT NULL::integer)
RETURNS public.requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
  row public.requests;
BEGIN
  v_uid := public.require_session_permissions(p_token, null);

  INSERT INTO public.requests (id, user_id, date, value, important_rank)
  VALUES (gen_random_uuid(), v_uid, p_date, p_value, p_important_rank)
  ON CONFLICT (user_id, date) DO UPDATE
  SET value = p_value, important_rank = COALESCE(p_important_rank, EXCLUDED.important_rank)
  RETURNING * INTO row;

  RETURN row;
END;
$$;

-- Staff request shift swap (token-only)
CREATE OR REPLACE FUNCTION public.staff_request_shift_swap(
  p_token uuid,
  p_initiator_shift_date date,
  p_counterparty_user_id uuid,
  p_counterparty_shift_date date,
  p_period_id uuid DEFAULT NULL::uuid
)
RETURNS TABLE(success boolean, swap_request_id uuid, error_message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
  v_swap_req_id uuid;
  v_initiator_shift_id bigint;
  v_counterparty_shift_id bigint;
  v_initiator_shift_code text;
  v_counterparty_shift_code text;
  v_period_id_to_use uuid;
BEGIN
  v_uid := public.require_session_permissions(p_token, null);

  -- Use provided period or get active period
  IF p_period_id IS NOT NULL THEN
    v_period_id_to_use := p_period_id;
  ELSE
    SELECT id INTO v_period_id_to_use FROM public.rota_periods WHERE is_active = true;
  END IF;

  IF v_period_id_to_use IS NULL THEN
    RETURN QUERY SELECT false, null::uuid, 'no_active_period'::text;
    RETURN;
  END IF;

  -- Get initiator's shift
  SELECT ra.id, s.code INTO v_initiator_shift_id, v_initiator_shift_code
  FROM public.rota_assignments ra
  JOIN public.shifts s ON s.id = ra.shift_id
  WHERE ra.user_id = v_uid AND ra.date = p_initiator_shift_date AND ra.status = 'published'
  LIMIT 1;

  IF v_initiator_shift_id IS NULL THEN
    RETURN QUERY SELECT false, null::uuid,
      ('initiator_shift_not_found:user=' || v_uid || ',date=' || p_initiator_shift_date)::text;
    RETURN;
  END IF;

  -- Get counterparty's shift
  SELECT ra.id, s.code INTO v_counterparty_shift_id, v_counterparty_shift_code
  FROM public.rota_assignments ra
  JOIN public.shifts s ON s.id = ra.shift_id
  WHERE ra.user_id = p_counterparty_user_id AND ra.date = p_counterparty_shift_date AND ra.status = 'published'
  LIMIT 1;

  IF v_counterparty_shift_id IS NULL THEN
    RETURN QUERY SELECT false, null::uuid,
      ('counterparty_shift_not_found:user=' || p_counterparty_user_id || ',date=' || p_counterparty_shift_date)::text;
    RETURN;
  END IF;

  -- Create swap request
  v_swap_req_id := gen_random_uuid();
  INSERT INTO public.swap_requests (
    id,
    initiator_user_id,
    initiator_shift_date,
    initiator_shift_code,
    counterparty_user_id,
    counterparty_shift_date,
    counterparty_shift_code,
    status,
    period_id
  ) VALUES (
    v_swap_req_id,
    v_uid,
    p_initiator_shift_date,
    v_initiator_shift_code,
    p_counterparty_user_id,
    p_counterparty_shift_date,
    v_counterparty_shift_code,
    'pending',
    v_period_id_to_use
  );

  -- Create notification for counterparty
  INSERT INTO public.notifications (
    type,
    target_scope,
    target_user_id,
    requires_action,
    status,
    payload
  ) VALUES (
    'swap_request',
    'user',
    p_counterparty_user_id,
    true,
    'pending',
    jsonb_build_object(
      'swap_request_id', v_swap_req_id,
      'initiator_name', (SELECT name FROM public.users WHERE id = v_uid),
      'initiator_shift_code', v_initiator_shift_code,
      'initiator_date', p_initiator_shift_date,
      'counterparty_shift_code', v_counterparty_shift_code,
      'counterparty_date', p_counterparty_shift_date
    )
  );

  RETURN QUERY SELECT true, v_swap_req_id, null::text;
END;
$$;

-- Staff respond to swap request (token-only)
CREATE OR REPLACE FUNCTION public.staff_respond_to_swap_request(
  p_token uuid,
  p_swap_request_id uuid,
  p_response text
)
RETURNS TABLE(success boolean, error_message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
  v_swap_req public.swap_requests;
  v_counterparty_name text;
  v_initiator_name text;
  v_initiator_shift_id bigint;
  v_counterparty_shift_id bigint;
  v_initiator_old_shift_id bigint;
  v_counterparty_old_shift_id bigint;
  v_initiator_old_shift_code text;
  v_counterparty_old_shift_code text;
BEGIN
  v_uid := public.require_session_permissions(p_token, null);

  -- Fetch swap request
  SELECT * INTO v_swap_req FROM public.swap_requests WHERE id = p_swap_request_id;

  IF v_swap_req IS NULL THEN
    RETURN QUERY SELECT false, 'swap_request_not_found'::text;
    RETURN;
  END IF;

  -- Check that user is the counterparty
  IF v_swap_req.counterparty_user_id != v_uid THEN
    RETURN QUERY SELECT false, 'permission_denied: not the counterparty'::text;
    RETURN;
  END IF;

  -- Get names
  SELECT name INTO v_counterparty_name FROM public.users WHERE id = v_uid;
  SELECT name INTO v_initiator_name FROM public.users WHERE id = v_swap_req.initiator_user_id;

  -- Update swap request
  UPDATE public.swap_requests
  SET status = CASE
        WHEN p_response IN ('accept', 'accepted') THEN 'accepted_by_counterparty'::text
        WHEN p_response IN ('decline', 'declined') THEN 'declined_by_counterparty'::text
        ELSE 'ignored'::text
      END,
      counterparty_responded_at = now(),
      counterparty_response = p_response
  WHERE id = p_swap_request_id;

  -- If accepted, create notification for admins (no history/comments yet - wait for admin approval)
  IF p_response IN ('accept', 'accepted') THEN
    -- Insert notification for each admin user (staff approved their part, now needs admin approval)
    INSERT INTO public.notifications (
      type,
      target_scope,
      target_user_id,
      requires_action,
      status,
      payload
    )
    SELECT
      'swap_request',
      'user',
      u.id,
      true,
      'pending',
      jsonb_build_object(
        'swap_request_id', v_swap_req.id,
        'initiator_name', v_initiator_name,
        'initiator_shift_code', v_swap_req.initiator_shift_code,
        'initiator_date', v_swap_req.initiator_shift_date,
        'counterparty_name', v_counterparty_name,
        'counterparty_shift_code', v_swap_req.counterparty_shift_code,
        'counterparty_date', v_swap_req.counterparty_shift_date,
        'notification_type', 'swap_accepted'
      )
    FROM public.users u
    WHERE u.is_admin = true AND u.is_active = true;
  END IF;

  -- Mark the counterparty's original swap request notification as acknowledged
  UPDATE public.notifications
  SET status = 'ack'
  WHERE type = 'swap_request'
    AND target_user_id = v_uid
    AND payload::jsonb->>'swap_request_id' = p_swap_request_id::text
    AND (payload::jsonb->>'notification_type' IS NULL OR payload::jsonb->>'notification_type' != 'swap_accepted');

  RETURN QUERY SELECT true, null::text;
EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT false, SQLERRM::text;
END;
$$;

-- Get pending swap requests for me (token-only, keep existing single-param overload)
CREATE OR REPLACE FUNCTION public.get_pending_swap_requests_for_me(p_token uuid)
RETURNS TABLE(
  id uuid,
  initiator_name text,
  counterparty_name text,
  initiator_shift_date date,
  initiator_shift_code text,
  counterparty_shift_date date,
  counterparty_shift_code text,
  created_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := public.require_session_permissions(p_token, null);

  RETURN QUERY
  SELECT
    sr.id,
    u_init.name,
    u_cnt.name,
    sr.initiator_shift_date,
    s_init.code,
    sr.counterparty_shift_date,
    s_cnt.code,
    sr.created_at
  FROM public.swap_requests sr
  JOIN public.users u_init ON u_init.id = sr.initiator_user_id
  JOIN public.users u_cnt ON u_cnt.id = sr.counterparty_user_id
  JOIN public.rota_assignments ra_init ON ra_init.user_id = sr.initiator_user_id
    AND ra_init.date = sr.initiator_shift_date
  JOIN public.shifts s_init ON s_init.id = ra_init.shift_id
  JOIN public.rota_assignments ra_cnt ON ra_cnt.user_id = sr.counterparty_user_id
    AND ra_cnt.date = sr.counterparty_shift_date
  JOIN public.shifts s_cnt ON s_cnt.id = ra_cnt.shift_id
  WHERE sr.counterparty_user_id = v_uid
    AND sr.status = 'pending'
  ORDER BY sr.created_at DESC;
END;
$$;

-- ============================================================================
-- PHASE 3: Recreate admin RPCs as token-only with is_admin bypass
-- ============================================================================

-- Admin execute shift swap
CREATE OR REPLACE FUNCTION public.admin_execute_shift_swap(
  p_token uuid,
  p_initiator_user_id uuid,
  p_initiator_shift_date date,
  p_counterparty_user_id uuid,
  p_counterparty_shift_date date,
  p_period_id uuid DEFAULT NULL::uuid
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
  v_period_id_to_use uuid;
  v_initiator_old_shift_id bigint;
  v_counterparty_old_shift_id bigint;
BEGIN
  -- Verify session and get admin user ID
  v_admin_uid := public.require_session_permissions(p_token, null);

  -- Check admin status
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    -- Non-admin must have manage_shifts permission
    PERFORM public.require_session_permissions(p_token, ARRAY['manage_shifts']);
  END IF;

  -- Use provided period or get active period
  IF p_period_id IS NOT NULL THEN
    v_period_id_to_use := p_period_id;
  ELSE
    SELECT id INTO v_period_id_to_use FROM public.rota_periods WHERE is_active = true;
  END IF;

  IF v_period_id_to_use IS NULL THEN
    RETURN QUERY SELECT false, null::uuid, 'no_active_period'::text;
    RETURN;
  END IF;

  -- Get initiator's current published shift
  SELECT id INTO v_initiator_shift_id
  FROM public.rota_assignments
  WHERE user_id = p_initiator_user_id AND date = p_initiator_shift_date AND status = 'published'
  LIMIT 1;

  IF v_initiator_shift_id IS NULL THEN
    RETURN QUERY SELECT false, null::uuid,
      ('initiator_shift_not_found:user=' || p_initiator_user_id || ',date=' || p_initiator_shift_date)::text;
    RETURN;
  END IF;

  -- Get counterparty's current published shift
  SELECT id INTO v_counterparty_shift_id
  FROM public.rota_assignments
  WHERE user_id = p_counterparty_user_id AND date = p_counterparty_shift_date AND status = 'published'
  LIMIT 1;

  IF v_counterparty_shift_id IS NULL THEN
    RETURN QUERY SELECT false, null::uuid,
      ('counterparty_shift_not_found:user=' || p_counterparty_user_id || ',date=' || p_counterparty_shift_date)::text;
    RETURN;
  END IF;

  -- Get the shift IDs for the old assignments
  SELECT shift_id INTO v_initiator_old_shift_id FROM public.rota_assignments WHERE id = v_initiator_shift_id;
  SELECT shift_id INTO v_counterparty_old_shift_id FROM public.rota_assignments WHERE id = v_counterparty_shift_id;

  -- Swap the shifts AND dates, maintain published status
  UPDATE public.rota_assignments SET shift_id = v_counterparty_old_shift_id, date = p_counterparty_shift_date, status = 'published' WHERE id = v_initiator_shift_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, null::uuid, 'failed_to_update_initiator_assignment'::text;
    RETURN;
  END IF;

  UPDATE public.rota_assignments SET shift_id = v_initiator_old_shift_id, date = p_initiator_shift_date, status = 'published' WHERE id = v_counterparty_shift_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, null::uuid, 'failed_to_update_counterparty_assignment'::text;
    RETURN;
  END IF;

  v_swap_exec_id := gen_random_uuid();
  INSERT INTO public.swap_executions (
    id,
    initiator_user_id,
    initiator_name,
    initiator_old_shift_date,
    initiator_new_shift_date,
    initiator_old_shift_code,
    initiator_new_shift_code,
    counterparty_user_id,
    counterparty_name,
    counterparty_old_shift_date,
    counterparty_new_shift_date,
    counterparty_old_shift_code,
    counterparty_new_shift_code,
    authoriser_user_id,
    authoriser_name,
    method,
    period_id
  ) VALUES (
    v_swap_exec_id,
    p_initiator_user_id,
    (SELECT name FROM public.users WHERE id = p_initiator_user_id),
    p_initiator_shift_date,
    p_counterparty_shift_date,
    COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
    COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
    p_counterparty_user_id,
    (SELECT name FROM public.users WHERE id = p_counterparty_user_id),
    p_counterparty_shift_date,
    p_initiator_shift_date,
    COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
    COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
    v_admin_uid,
    (SELECT name FROM public.users WHERE id = v_admin_uid),
    'admin_direct',
    v_period_id_to_use
  );

  -- Add system comments to both affected assignments
  IF to_regclass('public.rota_assignment_comments') IS NOT NULL THEN
    INSERT INTO public.rota_assignment_comments(rota_assignment_id, comment, is_admin_only, created_by, created_at)
    SELECT v_initiator_shift_id,
      format('%s swapped with %s. Was on %s (%s), now on %s (%s). Admin: %s',
        (SELECT name FROM public.users WHERE id = p_initiator_user_id),
        (SELECT name FROM public.users WHERE id = p_counterparty_user_id),
        to_char(p_initiator_shift_date, 'Dy DD Mon'),
        COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
        to_char(p_counterparty_shift_date, 'Dy DD Mon'),
        COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
        (SELECT name FROM public.users WHERE id = v_admin_uid)),
      false, v_admin_uid, now();

    INSERT INTO public.rota_assignment_comments(rota_assignment_id, comment, is_admin_only, created_by, created_at)
    SELECT v_counterparty_shift_id,
      format('%s swapped with %s. Was on %s (%s), now on %s (%s). Admin: %s',
        (SELECT name FROM public.users WHERE id = p_counterparty_user_id),
        (SELECT name FROM public.users WHERE id = p_initiator_user_id),
        to_char(p_counterparty_shift_date, 'Dy DD Mon'),
        COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
        to_char(p_initiator_shift_date, 'Dy DD Mon'),
        COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
        (SELECT name FROM public.users WHERE id = v_admin_uid)),
      false, v_admin_uid, now();
  END IF;

  -- Record history for both assignments (admin swap)
  IF to_regclass('public.rota_assignment_history') IS NOT NULL THEN
    INSERT INTO public.rota_assignment_history(
      rota_assignment_id,
      user_id,
      date,
      old_shift_id,
      old_shift_code,
      new_shift_id,
      new_shift_code,
      change_reason,
      changed_by,
      changed_by_name
    ) VALUES (
      v_initiator_shift_id,
      p_initiator_user_id,
      p_counterparty_shift_date,
      v_initiator_old_shift_id,
      COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
      v_counterparty_old_shift_id,
      COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
      format('Admin swap with %s on %s', (SELECT name FROM public.users WHERE id = p_counterparty_user_id), to_char(p_counterparty_shift_date, 'Dy DD Mon')),
      v_admin_uid,
      (SELECT name FROM public.users WHERE id = v_admin_uid)
    );

    INSERT INTO public.rota_assignment_history(
      rota_assignment_id,
      user_id,
      date,
      old_shift_id,
      old_shift_code,
      new_shift_id,
      new_shift_code,
      change_reason,
      changed_by,
      changed_by_name
    ) VALUES (
      v_counterparty_shift_id,
      p_counterparty_user_id,
      p_initiator_shift_date,
      v_counterparty_old_shift_id,
      COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
      v_initiator_old_shift_id,
      COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
      format('Admin swap with %s on %s', (SELECT name FROM public.users WHERE id = p_initiator_user_id), to_char(p_initiator_shift_date, 'Dy DD Mon')),
      v_admin_uid,
      (SELECT name FROM public.users WHERE id = v_admin_uid)
    );
  END IF;

  RETURN QUERY SELECT true, v_swap_exec_id, null::text;
EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT false, null::uuid, SQLERRM::text;
END;
$$;

-- Admin get swap requests
CREATE OR REPLACE FUNCTION public.admin_get_swap_requests(p_token uuid)
RETURNS TABLE(
  id uuid,
  period_id uuid,
  initiator_name text,
  counterparty_name text,
  initiator_shift_date date,
  initiator_shift_code text,
  counterparty_shift_date date,
  counterparty_shift_code text,
  status text,
  counterparty_response text,
  counterparty_responded_at timestamp without time zone,
  created_at timestamp without time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
BEGIN
  -- Verify session
  v_admin_uid := public.require_session_permissions(p_token, null);

  -- Check admin status
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['manage_shifts']);
  END IF;

  RETURN QUERY
  SELECT
    sr.id,
    sr.period_id,
    u_init.name,
    u_cnt.name,
    sr.initiator_shift_date,
    s_init.code,
    sr.counterparty_shift_date,
    s_cnt.code,
    sr.status,
    sr.counterparty_response,
    sr.counterparty_responded_at,
    sr.created_at
  FROM public.swap_requests sr
  JOIN public.users u_init ON u_init.id = sr.initiator_user_id
  JOIN public.users u_cnt ON u_cnt.id = sr.counterparty_user_id
  JOIN public.rota_assignments ra_init ON ra_init.user_id = sr.initiator_user_id
    AND ra_init.date = sr.initiator_shift_date
  JOIN public.shifts s_init ON s_init.id = ra_init.shift_id
  JOIN public.rota_assignments ra_cnt ON ra_cnt.user_id = sr.counterparty_user_id
    AND ra_cnt.date = sr.counterparty_shift_date
  JOIN public.shifts s_cnt ON s_cnt.id = ra_cnt.shift_id
  ORDER BY sr.created_at DESC;
END;
$$;

-- Admin approve swap request
CREATE OR REPLACE FUNCTION public.admin_approve_swap_request(p_token uuid, p_swap_request_id uuid)
RETURNS TABLE(success boolean, swap_execution_id uuid, error_message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
  v_swap_req public.swap_requests;
  v_swap_exec_id uuid;
  v_initiator_shift_id bigint;
  v_counterparty_shift_id bigint;
  v_initiator_old_shift_id bigint;
  v_counterparty_old_shift_id bigint;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);

  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['manage_shifts']);
  END IF;

  SELECT * INTO v_swap_req FROM public.swap_requests WHERE id = p_swap_request_id;
  IF v_swap_req IS NULL THEN
    RETURN QUERY SELECT false, null::uuid, 'swap_request_not_found'::text;
    RETURN;
  END IF;

  -- Get shift IDs
  SELECT id INTO v_initiator_shift_id
  FROM public.rota_assignments
  WHERE user_id = v_swap_req.initiator_user_id AND date = v_swap_req.initiator_shift_date AND status = 'published'
  LIMIT 1;

  SELECT id INTO v_counterparty_shift_id
  FROM public.rota_assignments
  WHERE user_id = v_swap_req.counterparty_user_id AND date = v_swap_req.counterparty_shift_date AND status = 'published'
  LIMIT 1;

  IF v_initiator_shift_id IS NULL OR v_counterparty_shift_id IS NULL THEN
    RETURN QUERY SELECT false, null::uuid, 'shift_not_found'::text;
    RETURN;
  END IF;

  -- Get old shift IDs
  SELECT shift_id INTO v_initiator_old_shift_id FROM public.rota_assignments WHERE id = v_initiator_shift_id;
  SELECT shift_id INTO v_counterparty_old_shift_id FROM public.rota_assignments WHERE id = v_counterparty_shift_id;

  -- Perform swap and maintain published status - swap both shift_id AND dates
  UPDATE public.rota_assignments SET shift_id = v_counterparty_old_shift_id, date = v_swap_req.counterparty_shift_date, status = 'published' WHERE id = v_initiator_shift_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, null::uuid, 'failed_to_update_initiator_assignment'::text;
    RETURN;
  END IF;

  UPDATE public.rota_assignments SET shift_id = v_initiator_old_shift_id, date = v_swap_req.initiator_shift_date, status = 'published' WHERE id = v_counterparty_shift_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, null::uuid, 'failed_to_update_counterparty_assignment'::text;
    RETURN;
  END IF;

  -- Record execution
  v_swap_exec_id := gen_random_uuid();
  INSERT INTO public.swap_executions (
    id,
    initiator_user_id,
    initiator_name,
    initiator_old_shift_date,
    initiator_new_shift_date,
    initiator_old_shift_code,
    initiator_new_shift_code,
    counterparty_user_id,
    counterparty_name,
    counterparty_old_shift_date,
    counterparty_new_shift_date,
    counterparty_old_shift_code,
    counterparty_new_shift_code,
    authoriser_user_id,
    authoriser_name,
    method,
    swap_request_id,
    period_id
  ) VALUES (
    v_swap_exec_id,
    v_swap_req.initiator_user_id,
    (SELECT name FROM public.users WHERE id = v_swap_req.initiator_user_id),
    v_swap_req.initiator_shift_date,
    v_swap_req.counterparty_shift_date,
    COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
    COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
    v_swap_req.counterparty_user_id,
    (SELECT name FROM public.users WHERE id = v_swap_req.counterparty_user_id),
    v_swap_req.counterparty_shift_date,
    v_swap_req.initiator_shift_date,
    COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
    COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
    v_admin_uid,
    (SELECT name FROM public.users WHERE id = v_admin_uid),
    'admin_approved_request',
    p_swap_request_id,
    v_swap_req.period_id
  );

  -- Add system comments to both affected assignments
  IF to_regclass('public.rota_assignment_comments') IS NOT NULL THEN
    INSERT INTO public.rota_assignment_comments(rota_assignment_id, comment, is_admin_only, created_by, created_at)
    SELECT v_initiator_shift_id,
      format('%s swapped shift with %s: was working %s on %s, now working %s on %s. Approved by Admin %s',
        (SELECT name FROM public.users WHERE id = v_swap_req.initiator_user_id),
        (SELECT name FROM public.users WHERE id = v_swap_req.counterparty_user_id),
        COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
        to_char(v_swap_req.initiator_shift_date, 'Dy DD Mon'),
        COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
        to_char(v_swap_req.counterparty_shift_date, 'Dy DD Mon'),
        (SELECT name FROM public.users WHERE id = v_admin_uid)),
      false, v_admin_uid, now();

    INSERT INTO public.rota_assignment_comments(rota_assignment_id, comment, is_admin_only, created_by, created_at)
    SELECT v_counterparty_shift_id,
      format('%s swapped shift with %s: was working %s on %s, now working %s on %s. Approved by Admin %s',
        (SELECT name FROM public.users WHERE id = v_swap_req.counterparty_user_id),
        (SELECT name FROM public.users WHERE id = v_swap_req.initiator_user_id),
        COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
        to_char(v_swap_req.counterparty_shift_date, 'Dy DD Mon'),
        COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
        to_char(v_swap_req.initiator_shift_date, 'Dy DD Mon'),
        (SELECT name FROM public.users WHERE id = v_admin_uid)),
      false, v_admin_uid, now();
  END IF;

  -- Record history for both staff members
  IF to_regclass('public.rota_assignment_history') IS NOT NULL THEN
    INSERT INTO public.rota_assignment_history (
      rota_assignment_id, user_id, date,
      old_shift_id, old_shift_code,
      new_shift_id, new_shift_code,
      change_reason, changed_by, changed_by_name
    ) VALUES (
      v_initiator_shift_id,
      v_swap_req.initiator_user_id,
      v_swap_req.counterparty_shift_date,
      v_initiator_old_shift_id,
      COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
      v_counterparty_old_shift_id,
      COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
      format('Shift swap with %s approved by Admin %s', (SELECT name FROM public.users WHERE id = v_swap_req.counterparty_user_id), (SELECT name FROM public.users WHERE id = v_admin_uid)),
      v_admin_uid,
      (SELECT name FROM public.users WHERE id = v_admin_uid)
    );

    INSERT INTO public.rota_assignment_history (
      rota_assignment_id, user_id, date,
      old_shift_id, old_shift_code,
      new_shift_id, new_shift_code,
      change_reason, changed_by, changed_by_name
    ) VALUES (
      v_counterparty_shift_id,
      v_swap_req.counterparty_user_id,
      v_swap_req.initiator_shift_date,
      v_counterparty_old_shift_id,
      COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
      v_initiator_old_shift_id,
      COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
      format('Shift swap with %s approved by Admin %s', (SELECT name FROM public.users WHERE id = v_swap_req.initiator_user_id), (SELECT name FROM public.users WHERE id = v_admin_uid)),
      v_admin_uid,
      (SELECT name FROM public.users WHERE id = v_admin_uid)
    );
  END IF;

  -- Update swap request status
  UPDATE public.swap_requests SET status = 'approved_by_admin' WHERE id = p_swap_request_id;

  -- Mark all admin notifications for this swap as acknowledged
  UPDATE public.notifications
  SET status = 'ack'
  WHERE type = 'swap_request'
    AND payload::jsonb->>'swap_request_id' = p_swap_request_id::text
    AND payload::jsonb->>'notification_type' = 'swap_accepted';

  RETURN QUERY SELECT true, v_swap_exec_id, null::text;
EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT false, null::uuid, SQLERRM::text;
END;
$$;

-- Admin decline swap request
CREATE OR REPLACE FUNCTION public.admin_decline_swap_request(p_token uuid, p_swap_request_id uuid)
RETURNS TABLE(success boolean, error_message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
  v_swap_req public.swap_requests;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);

  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['manage_shifts']);
  END IF;

  SELECT * INTO v_swap_req FROM public.swap_requests WHERE id = p_swap_request_id;
  IF v_swap_req IS NULL THEN
    RETURN QUERY SELECT false, 'swap_request_not_found'::text;
    RETURN;
  END IF;

  UPDATE public.swap_requests SET status = 'declined_by_admin' WHERE id = p_swap_request_id;

  -- Mark all admin notifications for this swap as acknowledged
  UPDATE public.notifications
  SET status = 'ack'
  WHERE type = 'swap_request'
    AND payload::jsonb->>'swap_request_id' = p_swap_request_id::text
    AND payload::jsonb->>'notification_type' = 'swap_accepted';

  RETURN QUERY SELECT true, null::text;
EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT false, SQLERRM::text;
END;
$$;

-- Admin get swap executions
CREATE OR REPLACE FUNCTION public.admin_get_swap_executions(p_token uuid, p_period_id uuid DEFAULT NULL::uuid)
RETURNS TABLE(
  id uuid,
  period_id uuid,
  initiator_name text,
  counterparty_name text,
  authoriser_name text,
  initiator_date date,
  initiator_old_shift text,
  initiator_new_shift text,
  counterparty_date date,
  counterparty_old_shift text,
  counterparty_new_shift text,
  method text,
  executed_at timestamp without time zone
)
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
    PERFORM public.require_session_permissions(p_token, ARRAY['manage_shifts']);
  END IF;

  RETURN QUERY
  SELECT
    se.id,
    se.period_id,
    u_init.name,
    u_cnt.name,
    u_auth.name,
    se.initiator_shift_date,
    s_init_old.code,
    s_init_new.code,
    se.counterparty_shift_date,
    s_cnt_old.code,
    s_cnt_new.code,
    se.method,
    se.created_at
  FROM public.swap_executions se
  JOIN public.users u_init ON u_init.id = se.initiator_user_id
  JOIN public.users u_cnt ON u_cnt.id = se.counterparty_user_id
  JOIN public.users u_auth ON u_auth.id = se.authoriser_user_id
  JOIN public.rota_assignments ra_init_before ON ra_init_before.user_id = se.initiator_user_id
    AND ra_init_before.date = se.initiator_shift_date
  JOIN public.shifts s_init_old ON s_init_old.id = ra_init_before.shift_id
  JOIN public.rota_assignments ra_cnt_before ON ra_cnt_before.user_id = se.counterparty_user_id
    AND ra_cnt_before.date = se.counterparty_shift_date
  JOIN public.shifts s_cnt_old ON s_cnt_old.id = ra_cnt_before.shift_id
  LEFT JOIN public.shifts s_init_new ON s_init_new.id = (
    SELECT shift_id FROM public.rota_assignments
    WHERE user_id = se.initiator_user_id AND date = se.initiator_shift_date
  )
  LEFT JOIN public.shifts s_cnt_new ON s_cnt_new.id = (
    SELECT shift_id FROM public.rota_assignments
    WHERE user_id = se.counterparty_user_id AND date = se.counterparty_shift_date
  )
  WHERE (p_period_id IS NULL OR se.period_id = p_period_id)
  ORDER BY se.created_at DESC;
END;
$$;

-- ============================================================================
-- Notice admin functions
-- ============================================================================

-- Admin get all notices
CREATE OR REPLACE FUNCTION public.admin_get_all_notices(p_token uuid)
RETURNS TABLE(
  notice_id uuid,
  title text,
  body_en text,
  body_es text,
  version integer,
  is_active boolean,
  updated_at timestamp with time zone,
  created_by_name text,
  target_all boolean,
  target_roles integer[]
)
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
    PERFORM public.require_session_permissions(p_token, ARRAY['notices.view_admin']);
  END IF;

  RETURN QUERY
  SELECT
    n.id,
    n.title,
    n.body_en,
    n.body_es,
    n.version,
    n.is_active,
    n.updated_at,
    u.name,
    n.target_all,
    COALESCE(array_agg(nt.role_id) FILTER (WHERE nt.role_id IS NOT NULL), '{}'::integer[])
  FROM public.notices n
  LEFT JOIN public.users u ON u.id = n.created_by
  LEFT JOIN public.notice_targets nt ON nt.notice_id = n.id
  GROUP BY n.id, u.id
  ORDER BY n.updated_at DESC;
END;
$$;

-- Admin get notice acks
CREATE OR REPLACE FUNCTION public.admin_get_notice_acks(p_token uuid, p_notice_id uuid)
RETURNS TABLE(acked jsonb, pending jsonb)
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
  SELECT
    jsonb_agg(jsonb_build_object('user_id', na.user_id, 'name', u.name, 'acknowledged_at', na.acknowledged_at))
      FILTER (WHERE na.notice_id IS NOT NULL),
    jsonb_agg(jsonb_build_object('user_id', u2.id, 'name', u2.name))
      FILTER (WHERE na.notice_id IS NULL)
  FROM public.users u2
  LEFT JOIN public.notice_ack na ON na.notice_id = p_notice_id AND na.user_id = u2.id
  LEFT JOIN public.users u ON u.id = na.user_id
  WHERE p_notice_id IS NOT NULL;
END;
$$;

-- Admin upsert notice
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
    UPDATE public.notices
    SET title = p_title, body_en = p_body_en, body_es = p_body_es, target_all = p_target_all
    WHERE id = v_id;
  END IF;

  -- Update target roles
  DELETE FROM public.notice_targets WHERE notice_id = v_id;
  INSERT INTO public.notice_targets (notice_id, role_id)
  SELECT v_id, UNNEST(p_target_roles);

  RETURN v_id;
END;
$$;

-- Admin delete notice
CREATE OR REPLACE FUNCTION public.admin_delete_notice(p_token uuid, p_notice_id uuid)
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
    PERFORM public.require_session_permissions(p_token, ARRAY['notices.delete']);
  END IF;

  DELETE FROM public.notice_targets WHERE notice_id = p_notice_id;
  DELETE FROM public.notice_ack WHERE notice_id = p_notice_id;
  DELETE FROM public.notices WHERE id = p_notice_id;
END;
$$;

-- Admin set notice active
CREATE OR REPLACE FUNCTION public.admin_set_notice_active(p_token uuid, p_notice_id uuid, p_active boolean)
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
    PERFORM public.require_session_permissions(p_token, ARRAY['notices.toggle_active']);
  END IF;

  UPDATE public.notices SET is_active = p_active WHERE id = p_notice_id;
END;
$$;

-- ============================================================================
-- Period admin functions
-- ============================================================================

-- Admin set active period
CREATE OR REPLACE FUNCTION public.admin_set_active_period(p_token uuid, p_period_id uuid)
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
    PERFORM public.require_session_permissions(p_token, ARRAY['periods.set_active']);
  END IF;

  UPDATE public.rota_periods SET is_active = false WHERE is_active = true;
  UPDATE public.rota_periods SET is_active = true WHERE id = p_period_id;
END;
$$;

-- Admin set period closes at
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

-- Admin toggle hidden period
CREATE OR REPLACE FUNCTION public.admin_toggle_hidden_period(p_token uuid, p_period_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
  v_current boolean;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);

  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['periods.toggle_hidden']);
  END IF;

  SELECT is_hidden INTO v_current FROM public.rota_periods WHERE id = p_period_id;
  UPDATE public.rota_periods SET is_hidden = NOT v_current WHERE id = p_period_id;
END;
$$;

-- Admin set period hidden
CREATE OR REPLACE FUNCTION public.admin_set_period_hidden(p_token uuid, p_period_id uuid, p_hidden boolean)
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
    PERFORM public.require_session_permissions(p_token, ARRAY['periods.toggle_hidden']);
  END IF;

  UPDATE public.rota_periods SET is_hidden = p_hidden WHERE id = p_period_id;
END;
$$;

-- ============================================================================
-- Request admin functions
-- ============================================================================

-- Admin set request cell
CREATE OR REPLACE FUNCTION public.admin_set_request_cell(
  p_token uuid,
  p_target_user_id uuid,
  p_date date,
  p_value text,
  p_important_rank smallint DEFAULT NULL::smallint
)
RETURNS TABLE(
  out_id uuid,
  out_user_id uuid,
  out_date date,
  out_value text,
  out_important_rank smallint
)
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

-- Admin clear request cell
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

-- Admin lock request cell
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

-- Admin unlock request cell
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

-- ============================================================================
-- Week admin functions
-- ============================================================================

-- Admin set week open flags
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

  UPDATE public.rota_weeks
  SET is_open = p_open, is_open_after_close = p_open_after_close
  WHERE id = p_week_id;
END;
$$;

-- ============================================================================
-- User admin functions
-- ============================================================================

-- Admin upsert user
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
    INSERT INTO public.users (id, name, role_id, is_active)
    VALUES (v_id, p_name, p_role_id, true);
  ELSE
    v_id := p_user_id;
    UPDATE public.users SET name = p_name, role_id = p_role_id WHERE id = v_id;
  END IF;

  RETURN v_id;
END;
$$;

-- Admin toggle user active
CREATE OR REPLACE FUNCTION public.admin_set_user_active(p_token uuid, p_user_id uuid, p_active boolean)
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

-- Admin set user PIN (without requiring old PIN)
CREATE OR REPLACE FUNCTION public.admin_set_user_pin(p_token uuid, p_user_id uuid, p_new_pin text)
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
    PERFORM public.require_session_permissions(p_token, ARRAY['users.set_pin']);
  END IF;

  UPDATE public.users
  SET pin_hash = public.crypt(p_new_pin, public.gen_salt('bf'))
  WHERE id = p_user_id;
END;
$$;

-- Admin reorder users
CREATE OR REPLACE FUNCTION public.admin_reorder_users(p_token uuid, p_user_id uuid, p_display_order integer)
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
    PERFORM public.require_session_permissions(p_token, ARRAY['users.reorder']);
  END IF;

  UPDATE public.users SET display_order = p_display_order WHERE id = p_user_id;
END;
$$;

-- ============================================================================
-- Admin impersonation function (for View As feature)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_impersonate_user(
  p_admin_token uuid,
  p_target_user_id uuid,
  p_ttl_hours integer DEFAULT 12
)
RETURNS TABLE(impersonation_token uuid, expires_at timestamp with time zone, error_message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
  v_new_token uuid;
  v_expires_at timestamp with time zone;
BEGIN
  -- Validate admin token
  BEGIN
    v_admin_uid := public.require_session_permissions(p_admin_token, null);
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT null::uuid, null::timestamp with time zone, 'invalid_token'::text;
    RETURN;
  END;

  -- Confirm admin
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    RETURN QUERY SELECT null::uuid, null::timestamp with time zone, 'not_admin'::text;
    RETURN;
  END IF;

  -- TTL sanity check
  IF p_ttl_hours IS NULL OR p_ttl_hours < 1 OR p_ttl_hours > 72 THEN
    p_ttl_hours := 12;
  END IF;

  -- Generate impersonation token
  v_new_token := gen_random_uuid();
  v_expires_at := now() + (p_ttl_hours || ' hours')::interval;

  -- Insert into sessions table
  INSERT INTO public.sessions(token, user_id, expires_at)
  VALUES (v_new_token, p_target_user_id, v_expires_at);

  RETURN QUERY SELECT v_new_token, v_expires_at, null::text;

EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT null::uuid, null::timestamp with time zone, SQLERRM::text;
END;
$$;

-- ============================================================================
-- COMMIT
-- ============================================================================

COMMIT;

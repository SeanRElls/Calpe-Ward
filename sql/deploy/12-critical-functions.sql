-- ============================================================================
-- RECREATE 12 CRITICAL TOKEN-ONLY FUNCTIONS
-- ============================================================================
-- These functions were dropped but are already being called with p_token from the frontend
-- They must be recreated immediately to restore application functionality
--
-- Source: Extracted from migrate_to_token_only_rpcs.sql (lines 521-1423)
-- Missing 3 created from scratch based on frontend requirements
-- ============================================================================

BEGIN;

-- ============================================================================
-- SWAP FUNCTIONS
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
    RETURN QUERY SELECT false, null::uuid, 'initiator_shift_not_found'::text;
    RETURN;
  END IF;

  -- Get counterparty's current published shift
  SELECT id INTO v_counterparty_shift_id
  FROM public.rota_assignments
  WHERE user_id = p_counterparty_user_id AND date = p_counterparty_shift_date AND status = 'published'
  LIMIT 1;

  IF v_counterparty_shift_id IS NULL THEN
    RETURN QUERY SELECT false, null::uuid, 'counterparty_shift_not_found'::text;
    RETURN;
  END IF;

  -- Get the shift IDs for the old assignments
  SELECT shift_id INTO v_initiator_old_shift_id FROM public.rota_assignments WHERE id = v_initiator_shift_id;
  SELECT shift_id INTO v_counterparty_old_shift_id FROM public.rota_assignments WHERE id = v_counterparty_shift_id;

  -- Swap the shifts
  UPDATE public.rota_assignments SET shift_id = v_counterparty_old_shift_id WHERE id = v_initiator_shift_id;
  UPDATE public.rota_assignments SET shift_id = v_initiator_old_shift_id WHERE id = v_counterparty_shift_id;

  -- Record the swap execution
  v_swap_exec_id := gen_random_uuid();
  INSERT INTO public.swap_executions (
    id,
    period_id,
    initiator_user_id,
    initiator_shift_date,
    counterparty_user_id,
    counterparty_shift_date,
    authoriser_user_id,
    method
  ) VALUES (
    v_swap_exec_id,
    v_period_id_to_use,
    p_initiator_user_id,
    p_initiator_shift_date,
    p_counterparty_user_id,
    p_counterparty_shift_date,
    v_admin_uid,
    'admin_direct'
  );

  RETURN QUERY SELECT true, v_swap_exec_id, null::text;
EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT false, null::uuid, SQLERRM::text;
END;
$$;

-- ============================================================================
-- NOTICE FUNCTIONS
-- ============================================================================

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
  SELECT
    n.id AS notice_id,
    COUNT(na.user_id) AS acked_count,
    (SELECT COUNT(*) FROM public.users WHERE is_active = true) - COUNT(na.user_id) AS pending_count
  FROM UNNEST(p_notice_ids) AS n(id)
  LEFT JOIN public.notice_ack na ON na.notice_id = n.id
  GROUP BY n.id;
END;
$$;

-- ============================================================================
-- PERIOD FUNCTIONS
-- ============================================================================

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
  v_period_start date;
  v_period_end date;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);

  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['periods.create']);
  END IF;

  IF p_start_date IS NULL THEN
    RAISE EXCEPTION 'start_date is required';
  END IF;

  -- Derive 5-week end date server-side to satisfy constraint
  v_period_start := p_start_date;
  v_period_end := p_start_date + INTERVAL '34 days';

  -- Create the period
  v_period_id := gen_random_uuid();
  INSERT INTO public.rota_periods (id, name, start_date, end_date, is_active, is_hidden)
  VALUES (v_period_id, p_name, v_period_start, v_period_end, false, false);

  -- Create 5 weeks
  v_week_start := v_period_start;
  FOR i IN 1..5 LOOP
    v_week_end := v_week_start + interval '6 days';
    IF v_week_end > v_period_end THEN
      v_week_end := v_period_end;
    END IF;

    v_week_id := gen_random_uuid();
    INSERT INTO public.rota_weeks (id, period_id, week_start, week_end, open, open_after_close)
    VALUES (v_week_id, v_period_id, v_week_start, v_week_end, false, false);

    -- Create date rows for each day in the week
    v_current_date := v_week_start;
    WHILE v_current_date <= v_week_end LOOP
      INSERT INTO public.rota_dates (week_id, period_id, date)
      VALUES (v_week_id, v_period_id, v_current_date);
      v_current_date := v_current_date + interval '1 day';
    END LOOP;

    v_week_start := v_week_end + interval '1 day';
  END LOOP;

  RETURN v_period_id;
END;
$$;

-- ============================================================================
-- REQUEST FUNCTIONS
-- ============================================================================

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

-- ============================================================================
-- WEEK FUNCTIONS
-- ============================================================================

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
  SET open = p_open, open_after_close = p_open_after_close
  WHERE id = p_week_id;
END;
$$;

-- ============================================================================
-- USER FUNCTIONS
-- ============================================================================

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

COMMIT;

-- ============================================================================
-- VERIFICATION QUERY
-- ============================================================================
-- Run this to confirm all 12 functions were created successfully:
--
-- SELECT routine_name, routine_type
-- FROM information_schema.routines
-- WHERE routine_schema = 'public'
--   AND routine_name IN (
--     'admin_execute_shift_swap',
--     'admin_upsert_notice',
--     'admin_notice_ack_counts',
--     'admin_set_period_closes_at',
--     'admin_create_five_week_period',
--     'admin_set_request_cell',
--     'admin_clear_request_cell',
--     'admin_lock_request_cell',
--     'admin_unlock_request_cell',
--     'admin_set_week_open_flags',
--     'admin_upsert_user',
--     'set_user_active'
--   )
-- ORDER BY routine_name;
-- 
-- Expected: 12 rows

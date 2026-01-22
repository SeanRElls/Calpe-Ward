BEGIN;

-- Admin upsert for assignment overrides
CREATE OR REPLACE FUNCTION public.admin_upsert_rota_assignment_override(
  p_token uuid,
  p_assignment_id bigint,
  p_override_start_time time,
  p_override_end_time time,
  p_override_hours numeric,
  p_comment text,
  p_comment_visibility text DEFAULT 'admin_only'
)
RETURNS public.rota_assignment_overrides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid;
  v_is_admin boolean;
  v_row public.rota_assignment_overrides;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['rota.edit_draft']);
  END IF;

  INSERT INTO public.rota_assignment_overrides(
    rota_assignment_id,
    override_start_time,
    override_end_time,
    override_hours,
    comment,
    comment_visibility,
    updated_at
  )
  VALUES (
    p_assignment_id,
    p_override_start_time,
    p_override_end_time,
    p_override_hours,
    p_comment,
    p_comment_visibility,
    now()
  )
  ON CONFLICT (rota_assignment_id)
  DO UPDATE SET
    override_start_time = EXCLUDED.override_start_time,
    override_end_time = EXCLUDED.override_end_time,
    override_hours = EXCLUDED.override_hours,
    comment = EXCLUDED.comment,
    comment_visibility = EXCLUDED.comment_visibility,
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_delete_rota_assignment_override(
  p_token uuid,
  p_assignment_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid; v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['rota.edit_draft']);
  END IF;
  DELETE FROM public.rota_assignment_overrides WHERE rota_assignment_id = p_assignment_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_insert_rota_assignment_history(
  p_token uuid,
  p_assignment_id bigint,
  p_user_id uuid,
  p_period_non_staff_id uuid,
  p_date date,
  p_old_shift_id bigint,
  p_old_shift_code text,
  p_new_shift_id bigint,
  p_new_shift_code text,
  p_change_reason text,
  p_changed_by_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid; v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['rota.edit_draft']);
  END IF;

  INSERT INTO public.rota_assignment_history(
    rota_assignment_id,
    user_id,
    period_non_staff_id,
    date,
    old_shift_id,
    old_shift_code,
    new_shift_id,
    new_shift_code,
    change_reason,
    changed_by,
    changed_by_name,
    changed_at
  )
  VALUES (
    p_assignment_id,
    p_user_id,
    p_period_non_staff_id,
    p_date,
    p_old_shift_id,
    p_old_shift_code,
    p_new_shift_id,
    p_new_shift_code,
    p_change_reason,
    v_uid,
    p_changed_by_name,
    now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_upsert_rota_assignment(
  p_token uuid,
  p_user_id uuid,
  p_period_non_staff_id uuid,
  p_date date,
  p_shift_id bigint,
  p_status text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid;
  v_is_admin boolean;
  v_id bigint;
  v_old_shift_id bigint;
  v_old_shift_code text;
  v_new_shift_code text;
  v_admin_name text;
  v_rota_published boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['rota.edit_draft']);
  END IF;

  SELECT id, shift_id INTO v_id, v_old_shift_id
  FROM public.rota_assignments
  WHERE date = p_date
    AND (
      (p_user_id IS NOT NULL AND user_id = p_user_id AND period_non_staff_id IS NULL)
      OR (p_period_non_staff_id IS NOT NULL AND period_non_staff_id = p_period_non_staff_id AND user_id IS NULL)
    )
  ORDER BY id DESC
  LIMIT 1;

  IF v_id IS NULL THEN
    INSERT INTO public.rota_assignments(user_id, period_non_staff_id, date, shift_id, status)
    VALUES (p_user_id, p_period_non_staff_id, p_date, p_shift_id, p_status)
    RETURNING id INTO v_id;
  ELSE
    -- Check if this is a published rota and shift is actually changing
    SELECT (status = 'published') INTO v_rota_published
    FROM public.rota_periods
    WHERE p_date BETWEEN start_date AND end_date
    ORDER BY published_at DESC NULLS LAST, created_at DESC
    LIMIT 1;

    IF COALESCE(v_rota_published, false) AND v_old_shift_id IS DISTINCT FROM p_shift_id THEN
      -- Get shift codes and admin name for history
      SELECT code INTO v_old_shift_code FROM public.shifts WHERE id = v_old_shift_id;
      SELECT code INTO v_new_shift_code FROM public.shifts WHERE id = p_shift_id;
      -- users table uses "name" column, not display_name
      SELECT name INTO v_admin_name FROM public.users WHERE id = v_uid;

      -- Record the change in history
      INSERT INTO public.rota_assignment_history(
        user_id,
        period_non_staff_id,
        date,
        old_shift_id,
        new_shift_id,
        old_shift_code,
        new_shift_code,
        change_reason,
        changed_by,
        changed_by_name,
        changed_at
      ) VALUES (
        p_user_id,
        p_period_non_staff_id,
        p_date,
        v_old_shift_id,
        p_shift_id,
        v_old_shift_code,
        v_new_shift_code,
        'Admin changed shift',
        v_uid,
        v_admin_name,
        now()
      );
    END IF;

    UPDATE public.rota_assignments
    SET shift_id = p_shift_id,
        status = COALESCE(p_status, status)
    WHERE id = v_id;
  END IF;

  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_delete_rota_assignment(
  p_token uuid,
  p_user_id uuid,
  p_period_non_staff_id uuid,
  p_date date
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid; v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['rota.edit_draft']);
  END IF;

  DELETE FROM public.rota_assignments
  WHERE date = p_date
    AND (
      (p_user_id IS NOT NULL AND user_id = p_user_id AND period_non_staff_id IS NULL)
      OR (p_period_non_staff_id IS NOT NULL AND period_non_staff_id = p_period_non_staff_id AND user_id IS NULL)
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_add_rota_assignment_comment(
  p_token uuid,
  p_assignment_id bigint,
  p_comment text,
  p_comment_visibility text DEFAULT 'all_staff'
)
RETURNS public.rota_assignment_comments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid;
  v_row public.rota_assignment_comments;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  INSERT INTO public.rota_assignment_comments(
    rota_assignment_id,
    comment,
    comment_visibility,
    created_by,
    updated_by,
    created_at,
    updated_at
  )
  VALUES (
    p_assignment_id,
    p_comment,
    p_comment_visibility,
    v_uid,
    v_uid,
    now(),
    now()
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_delete_rota_assignment_comment(
  p_token uuid,
  p_comment_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid; v_is_admin boolean; v_owner uuid;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  SELECT created_by INTO v_owner FROM public.rota_assignment_comments WHERE id = p_comment_id;

  IF COALESCE(v_is_admin, false) OR v_owner = v_uid THEN
    DELETE FROM public.rota_assignment_comments WHERE id = p_comment_id;
  ELSE
    RAISE EXCEPTION 'not_allowed';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_publish_rota_period(
  p_token uuid,
  p_period_id uuid
)
RETURNS public.rota_periods
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid;
  v_is_admin boolean;
  v_period public.rota_periods;
  v_now timestamptz := now();
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['rota.publish']);
  END IF;

  SELECT * INTO v_period FROM public.rota_periods WHERE id = p_period_id;
  IF v_period IS NULL THEN
    RAISE EXCEPTION 'period_not_found';
  END IF;

  UPDATE public.rota_periods
  SET status = 'published',
      published_at = v_now,
      published_by = v_uid,
      published_version = COALESCE(published_version, 0) + 1
  WHERE id = p_period_id
  RETURNING * INTO v_period;

  UPDATE public.rota_assignments
  SET status = 'published'
  WHERE date >= v_period.start_date
    AND date <= v_period.end_date
    AND status = 'draft';

  INSERT INTO public.rota_assignment_history(
    rota_assignment_id,
    user_id,
    period_non_staff_id,
    date,
    old_shift_id,
    old_shift_code,
    new_shift_id,
    new_shift_code,
    change_reason,
    changed_by,
    changed_by_name,
    changed_at
  )
  SELECT DISTINCT ON (COALESCE(ra.user_id::text, ra.period_non_staff_id::text), ra.date)
    ra.id,
    ra.user_id,
    ra.period_non_staff_id,
    ra.date,
    NULL::bigint,
    NULL::text,
    ra.shift_id,
    s.code,
    'Rota published',
    v_uid,
    (SELECT name FROM public.users WHERE id = v_uid),
    v_now
  FROM public.rota_assignments ra
  LEFT JOIN public.shifts s ON s.id = ra.shift_id
  WHERE ra.date >= v_period.start_date
    AND ra.date <= v_period.end_date
  ORDER BY COALESCE(ra.user_id::text, ra.period_non_staff_id::text), ra.date, ra.created_at DESC;

  RETURN v_period;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_unpublish_rota_period(
  p_token uuid,
  p_period_id uuid
)
RETURNS public.rota_periods
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid;
  v_is_admin boolean;
  v_period public.rota_periods;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['rota.publish']);
  END IF;

  SELECT * INTO v_period FROM public.rota_periods WHERE id = p_period_id;
  IF v_period IS NULL THEN
    RAISE EXCEPTION 'period_not_found';
  END IF;

  UPDATE public.rota_periods
  SET status = 'draft',
      published_at = NULL,
      published_by = NULL
  WHERE id = p_period_id
  RETURNING * INTO v_period;

  UPDATE public.rota_assignments
  SET status = 'draft'
  WHERE date >= v_period.start_date
    AND date <= v_period.end_date
    AND status = 'published';

  DELETE FROM public.rota_assignment_history
  WHERE date >= v_period.start_date
    AND date <= v_period.end_date;

  DELETE FROM public.swap_requests
  WHERE (initiator_shift_date BETWEEN v_period.start_date AND v_period.end_date)
     OR (counterparty_shift_date BETWEEN v_period.start_date AND v_period.end_date);

  DELETE FROM public.swap_executions
  WHERE (initiator_old_shift_date BETWEEN v_period.start_date AND v_period.end_date)
     OR (initiator_new_shift_date BETWEEN v_period.start_date AND v_period.end_date)
     OR (counterparty_old_shift_date BETWEEN v_period.start_date AND v_period.end_date)
     OR (counterparty_new_shift_date BETWEEN v_period.start_date AND v_period.end_date);

  DELETE FROM public.rota_assignment_comments
  WHERE rota_assignment_id IN (
    SELECT id FROM public.rota_assignments
    WHERE date >= v_period.start_date AND date <= v_period.end_date
  );

  RETURN v_period;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.admin_upsert_rota_assignment_override(uuid, bigint, time, time, numeric, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_rota_assignment_override(uuid, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_insert_rota_assignment_history(uuid, bigint, uuid, uuid, date, bigint, text, bigint, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_upsert_rota_assignment(uuid, uuid, uuid, date, bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_rota_assignment(uuid, uuid, uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_add_rota_assignment_comment(uuid, bigint, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_delete_rota_assignment_comment(uuid, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_publish_rota_period(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_unpublish_rota_period(uuid, uuid) TO authenticated;

COMMIT;

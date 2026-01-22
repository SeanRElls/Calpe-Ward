-- RPC surface to replace direct table access from frontend

BEGIN;

-- Basic users list for staff pages (no PIN hash)
CREATE OR REPLACE FUNCTION public.rpc_get_users_basic(p_token uuid, p_include_inactive boolean DEFAULT false)
RETURNS TABLE(
  id uuid,
  name text,
  role_id smallint,
  is_admin boolean,
  is_active boolean,
  display_order integer,
  preferred_lang text,
  username text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  RETURN QUERY
  SELECT u.id, u.name, u.role_id, u.is_admin, u.is_active, u.display_order, u.preferred_lang, u.username
  FROM public.users u
  WHERE (p_include_inactive OR u.is_active = true)
  ORDER BY u.display_order NULLS LAST, u.name;
END;
$function$;

-- Admin users list (no PIN hash)
CREATE OR REPLACE FUNCTION public.admin_get_users(p_token uuid, p_include_inactive boolean DEFAULT false)
RETURNS TABLE(
  id uuid,
  name text,
  role_id smallint,
  is_admin boolean,
  is_active boolean,
  display_order integer,
  preferred_lang text,
  username text,
  can_be_in_charge_day boolean,
  can_be_in_charge_night boolean,
  cannot_be_second_rn_day boolean,
  cannot_be_second_rn_night boolean,
  can_work_nights boolean,
  pref_shift_clustering integer,
  pref_night_appetite integer,
  pref_weekend_appetite integer,
  pref_leave_adjacency integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid;
  v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['system.admin_panel']);
  END IF;

  RETURN QUERY
  SELECT u.id, u.name, u.role_id, u.is_admin, u.is_active, u.display_order, u.preferred_lang, u.username,
         u.can_be_in_charge_day, u.can_be_in_charge_night, u.cannot_be_second_rn_day, u.cannot_be_second_rn_night,
         u.can_work_nights, u.pref_shift_clustering, u.pref_night_appetite, u.pref_weekend_appetite, u.pref_leave_adjacency
  FROM public.users u
  WHERE (p_include_inactive OR u.is_active = true)
  ORDER BY u.display_order NULLS LAST, u.name;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_user_by_id(p_token uuid, p_user_id uuid)
RETURNS TABLE(
  id uuid,
  name text,
  role_id smallint,
  is_admin boolean,
  is_active boolean,
  display_order integer,
  preferred_lang text,
  username text,
  can_be_in_charge_day boolean,
  can_be_in_charge_night boolean,
  cannot_be_second_rn_day boolean,
  cannot_be_second_rn_night boolean,
  can_work_nights boolean,
  pref_shift_clustering integer,
  pref_night_appetite integer,
  pref_weekend_appetite integer,
  pref_leave_adjacency integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid;
  v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['system.admin_panel']);
  END IF;

  RETURN QUERY
  SELECT u.id, u.name, u.role_id, u.is_admin, u.is_active, u.display_order, u.preferred_lang, u.username,
         u.can_be_in_charge_day, u.can_be_in_charge_night, u.cannot_be_second_rn_day, u.cannot_be_second_rn_night,
         u.can_work_nights, u.pref_shift_clustering, u.pref_night_appetite, u.pref_weekend_appetite, u.pref_leave_adjacency
  FROM public.users u
  WHERE u.id = p_user_id;
END;
$function$;

-- Rota metadata
CREATE OR REPLACE FUNCTION public.rpc_get_rota_periods(p_token uuid)
RETURNS SETOF public.rota_periods
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  RETURN QUERY SELECT * FROM public.rota_periods ORDER BY start_date;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_rota_weeks(p_token uuid, p_period_id uuid)
RETURNS SETOF public.rota_weeks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  RETURN QUERY SELECT * FROM public.rota_weeks WHERE period_id = p_period_id ORDER BY week_start;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_rota_dates(p_token uuid, p_period_id uuid)
RETURNS SETOF public.rota_dates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  RETURN QUERY SELECT * FROM public.rota_dates WHERE period_id = p_period_id ORDER BY date;
END;
$function$;

-- Shifts
CREATE OR REPLACE FUNCTION public.rpc_get_shifts(p_token uuid, p_allow_requests boolean DEFAULT NULL)
RETURNS SETOF public.shifts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  IF p_allow_requests IS NULL THEN
    RETURN QUERY SELECT * FROM public.shifts ORDER BY code;
  ELSE
    RETURN QUERY SELECT * FROM public.shifts WHERE allow_requests = p_allow_requests ORDER BY code;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_shifts(p_token uuid)
RETURNS SETOF public.shifts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid; v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['manage_shifts']);
  END IF;
  RETURN QUERY SELECT * FROM public.shifts ORDER BY code;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_upsert_shift(
  p_token uuid,
  p_shift_id bigint,
  p_code text,
  p_label text,
  p_hours_value numeric,
  p_start_time time DEFAULT NULL,
  p_end_time time DEFAULT NULL,
  p_day_or_night text DEFAULT NULL,
  p_allowed_staff_groups text DEFAULT NULL,
  p_allow_requests boolean DEFAULT true,
  p_allow_draft boolean DEFAULT true,
  p_allow_post_publish boolean DEFAULT false,
  p_fill_color text DEFAULT NULL,
  p_text_color text DEFAULT NULL,
  p_text_bold boolean DEFAULT false,
  p_text_italic boolean DEFAULT false,
  p_is_time_off boolean DEFAULT false
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid; v_is_admin boolean; v_id bigint;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['manage_shifts']);
  END IF;

  IF p_shift_id IS NULL THEN
    INSERT INTO public.shifts(
      code, label, hours_value, start_time, end_time, day_or_night, allowed_staff_groups,
      allow_requests, allow_draft, allow_post_publish, fill_color, text_color, text_bold, text_italic, is_time_off
    ) VALUES (
      p_code, p_label, p_hours_value, p_start_time, p_end_time, p_day_or_night, p_allowed_staff_groups,
      p_allow_requests, p_allow_draft, p_allow_post_publish, p_fill_color, p_text_color, p_text_bold, p_text_italic, p_is_time_off
    ) RETURNING id INTO v_id;
  ELSE
    UPDATE public.shifts
    SET code = p_code,
        label = p_label,
        hours_value = p_hours_value,
        start_time = p_start_time,
        end_time = p_end_time,
        day_or_night = p_day_or_night,
        allowed_staff_groups = p_allowed_staff_groups,
        allow_requests = p_allow_requests,
        allow_draft = p_allow_draft,
        allow_post_publish = p_allow_post_publish,
        fill_color = p_fill_color,
        text_color = p_text_color,
        text_bold = p_text_bold,
        text_italic = p_text_italic,
        is_time_off = p_is_time_off
    WHERE id = p_shift_id
    RETURNING id INTO v_id;
  END IF;

  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_delete_shift(p_token uuid, p_shift_id bigint)
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
    PERFORM public.require_session_permissions(p_token, ARRAY['manage_shifts']);
  END IF;
  DELETE FROM public.shifts WHERE id = p_shift_id;
END;
$function$;

-- Patterns
CREATE OR REPLACE FUNCTION public.rpc_get_pattern_definitions(p_token uuid)
RETURNS SETOF public.pattern_definitions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  RETURN QUERY SELECT * FROM public.pattern_definitions ORDER BY id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_user_patterns(p_token uuid)
RETURNS SETOF public.user_patterns
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  RETURN QUERY SELECT * FROM public.user_patterns;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_upsert_user_pattern(
  p_token uuid,
  p_user_id uuid,
  p_pattern_id uuid,
  p_anchor_week_start_date date
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
    PERFORM public.require_session_permissions(p_token, ARRAY['users.edit']);
  END IF;

  INSERT INTO public.user_patterns(user_id, pattern_id, anchor_week_start_date, assigned_by, assigned_at, updated_at)
  VALUES (p_user_id, p_pattern_id, p_anchor_week_start_date, v_uid, now(), now())
  ON CONFLICT (user_id)
  DO UPDATE SET pattern_id = EXCLUDED.pattern_id,
                anchor_week_start_date = EXCLUDED.anchor_week_start_date,
                assigned_by = v_uid,
                updated_at = now();
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_delete_user_pattern(p_token uuid, p_user_id uuid)
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
    PERFORM public.require_session_permissions(p_token, ARRAY['users.edit']);
  END IF;
  DELETE FROM public.user_patterns WHERE user_id = p_user_id;
END;
$function$;

-- Permissions admin
CREATE OR REPLACE FUNCTION public.admin_get_permissions(p_token uuid)
RETURNS SETOF public.permissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid; v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['system.admin_panel']);
  END IF;
  RETURN QUERY SELECT * FROM public.permissions ORDER BY category, key;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_permission_groups(p_token uuid)
RETURNS SETOF public.permission_groups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid; v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['system.admin_panel']);
  END IF;
  RETURN QUERY SELECT * FROM public.permission_groups ORDER BY name;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_permission_group_permissions(p_token uuid, p_group_id uuid)
RETURNS SETOF public.permission_group_permissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid; v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['system.admin_panel']);
  END IF;
  RETURN QUERY SELECT * FROM public.permission_group_permissions WHERE group_id = p_group_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_user_permission_groups(p_token uuid, p_user_id uuid)
RETURNS SETOF public.user_permission_groups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid; v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['system.admin_panel']);
  END IF;
  RETURN QUERY SELECT * FROM public.user_permission_groups WHERE user_id = p_user_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_permission_group_permissions(
  p_token uuid,
  p_group_id uuid,
  p_permission_keys text[]
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
    PERFORM public.require_session_permissions(p_token, ARRAY['system.admin_panel']);
  END IF;

  DELETE FROM public.permission_group_permissions WHERE group_id = p_group_id;

  INSERT INTO public.permission_group_permissions(group_id, permission_key)
  SELECT p_group_id, unnest(p_permission_keys);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_user_permission_groups(
  p_token uuid,
  p_user_id uuid,
  p_group_ids uuid[]
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
    PERFORM public.require_session_permissions(p_token, ARRAY['system.admin_panel']);
  END IF;

  DELETE FROM public.user_permission_groups WHERE user_id = p_user_id;
  INSERT INTO public.user_permission_groups(user_id, group_id)
  SELECT p_user_id, unnest(p_group_ids);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_create_permission_group(p_token uuid, p_name text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid; v_is_admin boolean; v_id uuid;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['system.admin_panel']);
  END IF;

  INSERT INTO public.permission_groups(name) VALUES (p_name) RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

-- Rota data
CREATE OR REPLACE FUNCTION public.rpc_get_rota_assignments(
  p_token uuid,
  p_period_id uuid,
  p_include_draft boolean DEFAULT false
)
RETURNS SETOF public.rota_assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid; v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;

  IF p_include_draft AND NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['rota.view_draft']);
  END IF;

  IF p_include_draft THEN
    RETURN QUERY
    SELECT ra.*
    FROM public.rota_assignments ra
    JOIN public.rota_dates rd ON rd.date = ra.date
    WHERE rd.period_id = p_period_id;
  ELSE
    RETURN QUERY
    SELECT ra.*
    FROM public.rota_assignments ra
    JOIN public.rota_dates rd ON rd.date = ra.date
    WHERE rd.period_id = p_period_id
      AND ra.status = 'published';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_rota_assignment_overrides(
  p_token uuid,
  p_assignment_ids bigint[]
)
RETURNS SETOF public.rota_assignment_overrides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid; v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;

  IF COALESCE(v_is_admin, false) THEN
    RETURN QUERY SELECT * FROM public.rota_assignment_overrides WHERE rota_assignment_id = ANY(p_assignment_ids);
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.rota_assignment_overrides
  WHERE rota_assignment_id = ANY(p_assignment_ids)
    AND COALESCE(comment_visibility, 'all_staff') != 'admin_only'
    AND COALESCE(comment_visible_to_user, true) = true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_rota_assignment_comments(
  p_token uuid,
  p_assignment_ids bigint[]
)
RETURNS SETOF public.rota_assignment_comments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid; v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;

  IF COALESCE(v_is_admin, false) THEN
    RETURN QUERY SELECT * FROM public.rota_assignment_comments WHERE rota_assignment_id = ANY(p_assignment_ids);
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.rota_assignment_comments
  WHERE rota_assignment_id = ANY(p_assignment_ids)
    AND is_admin_only = false;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_rota_assignment_history(
  p_token uuid,
  p_assignment_ids bigint[]
)
RETURNS SETOF public.rota_assignment_history
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid; v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['rota.view_history']);
  END IF;
  RETURN QUERY SELECT * FROM public.rota_assignment_history WHERE rota_assignment_id = ANY(p_assignment_ids);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_staffing_requirements(p_token uuid, p_period_id uuid)
RETURNS SETOF public.staffing_requirements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid; v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['staffing.requirements']);
  END IF;
  RETURN QUERY SELECT * FROM public.staffing_requirements WHERE period_id = p_period_id ORDER BY date;
END;
$function$;

-- Bulk open/close weeks in a period (admin only)
CREATE OR REPLACE FUNCTION public.admin_set_weeks_open_for_period(
  p_token uuid,
  p_period_id uuid,
  p_open boolean
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

  UPDATE public.rota_weeks
  SET open = p_open,
      open_after_close = p_open
  WHERE period_id = p_period_id;
END;
$function$;

-- Bulk update open_after_close without touching open
CREATE OR REPLACE FUNCTION public.admin_set_weeks_open_after_close(
  p_token uuid,
  p_period_id uuid,
  p_open_after_close boolean
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

  UPDATE public.rota_weeks
  SET open_after_close = p_open_after_close
  WHERE period_id = p_period_id;
END;
$function$;

-- Week comments report (admin)
CREATE OR REPLACE FUNCTION public.admin_get_week_comments_for_period(p_token uuid, p_period_id uuid)
RETURNS TABLE(
  week_start date,
  user_id uuid,
  user_name text,
  comment text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid; v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['requests.view_all']);
  END IF;

  RETURN QUERY
  SELECT rw.week_start, wc.user_id, u.name, wc.comment, wc.created_at
  FROM public.week_comments wc
  JOIN public.rota_weeks rw ON rw.id = wc.week_id
  JOIN public.users u ON u.id = wc.user_id
  WHERE rw.period_id = p_period_id
  ORDER BY rw.week_start, wc.created_at;
END;
$function$;

COMMIT;

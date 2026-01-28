-- Fix ambiguous column reference in admin_get_user_by_id
-- Date: 2026-01-28

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
  -- Fix: Qualify column references with table alias
  SELECT u.is_admin INTO v_is_admin FROM public.users u WHERE u.id = v_uid;
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

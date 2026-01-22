BEGIN;

CREATE OR REPLACE FUNCTION public.admin_upsert_staffing_requirement(
  p_token uuid,
  p_period_id uuid,
  p_date date,
  p_day_sn_required numeric,
  p_day_na_required numeric,
  p_night_sn_required numeric,
  p_night_na_required numeric
)
RETURNS void
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
    PERFORM public.require_session_permissions(p_token, ARRAY['staffing.requirements']);
  END IF;

  INSERT INTO public.staffing_requirements (
    period_id,
    date,
    day_sn_required,
    day_na_required,
    night_sn_required,
    night_na_required
  )
  VALUES (
    p_period_id,
    p_date,
    p_day_sn_required,
    p_day_na_required,
    p_night_sn_required,
    p_night_na_required
  )
  ON CONFLICT (period_id, date)
  DO UPDATE SET
    day_sn_required = EXCLUDED.day_sn_required,
    day_na_required = EXCLUDED.day_na_required,
    night_sn_required = EXCLUDED.night_sn_required,
    night_na_required = EXCLUDED.night_na_required,
    updated_at = NOW();
END;
$function$;

GRANT EXECUTE ON FUNCTION public.admin_upsert_staffing_requirement(
  uuid, uuid, date, numeric, numeric, numeric, numeric
) TO authenticated;

COMMIT;

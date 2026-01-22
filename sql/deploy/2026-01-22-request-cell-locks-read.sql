BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_get_request_cell_locks(
  p_token uuid,
  p_start_date date,
  p_end_date date
)
RETURNS SETOF public.request_cell_locks
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

  IF COALESCE(v_is_admin, false) THEN
    RETURN QUERY
      SELECT *
      FROM public.request_cell_locks
      WHERE date >= p_start_date AND date <= p_end_date;
  END IF;

  RETURN QUERY
    SELECT *
    FROM public.request_cell_locks
    WHERE user_id = v_uid
      AND date >= p_start_date AND date <= p_end_date;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_get_request_cell_locks(uuid, date, date) TO authenticated;

COMMIT;

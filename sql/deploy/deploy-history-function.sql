-- Deploy assignment history function
-- Run this in Supabase SQL Editor

BEGIN;

-- Drop existing function
DROP FUNCTION IF EXISTS public.admin_get_assignment_history_by_date(uuid, uuid, date) CASCADE;

-- Create the function with explicit column mapping
CREATE FUNCTION public.admin_get_assignment_history_by_date(
  p_token uuid, 
  p_user_id uuid, 
  p_date date
)
RETURNS TABLE(
  id uuid,
  rota_assignment_id bigint,
  date date,
  old_shift_code text,
  new_shift_code text,
  change_reason text,
  changed_by_name text,
  changed_at timestamp with time zone,
  override_start_time time without time zone,
  override_end_time time without time zone,
  override_hours numeric,
  override_comment text,
  override_created_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
BEGIN
  -- Verify token and get admin user ID
  v_admin_uid := public.require_session_permissions(p_token, null);

  -- Check if user is admin, otherwise require specific permission
  SELECT is_admin INTO v_is_admin
  FROM public.users AS users_table
  WHERE users_table.id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['rota.view_history']);
  END IF;

  -- Return assignment history with override data
  RETURN QUERY
  SELECT
    rota_assignment_history.id,
    rota_assignment_history.rota_assignment_id,
    rota_assignment_history.date,
    rota_assignment_history.old_shift_code,
    rota_assignment_history.new_shift_code,
    rota_assignment_history.change_reason,
    rota_assignment_history.changed_by_name,
    rota_assignment_history.changed_at,
    rota_assignment_overrides.override_start_time,
    rota_assignment_overrides.override_end_time,
    rota_assignment_overrides.override_hours,
    rota_assignment_overrides.comment,
    rota_assignment_overrides.created_at
  FROM public.rota_assignment_history
  LEFT JOIN public.rota_assignment_overrides
    ON rota_assignment_overrides.rota_assignment_id = rota_assignment_history.rota_assignment_id
  WHERE (rota_assignment_history.user_id = p_user_id 
         OR rota_assignment_history.period_non_staff_id = p_user_id)
    AND rota_assignment_history.date = p_date
  ORDER BY rota_assignment_history.changed_at DESC;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.admin_get_assignment_history_by_date(uuid, uuid, date) 
  TO authenticated, service_role;

COMMIT;

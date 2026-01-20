-- Deploy assignment history function
-- Run this in Supabase SQL Editor

BEGIN;

-- Drop existing function
DROP FUNCTION IF EXISTS public.admin_get_assignment_history_by_date(uuid, uuid, date) CASCADE;

-- Create the function
CREATE FUNCTION public.admin_get_assignment_history_by_date(p_token uuid, p_user_id uuid, p_date date)
RETURNS TABLE(
  id uuid,
  assignment_id bigint,
  assignment_date date,
  old_shift_code text,
  new_shift_code text,
  change_reason text,
  changed_by_name text,
  changed_at timestamp with time zone
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
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['rota.view_history']);
  END IF;

  -- Return assignment history for the specified user and date
  RETURN QUERY
  SELECT
    history.id,
    history.rota_assignment_id,
    history.date,
    history.old_shift_code,
    history.new_shift_code,
    history.change_reason,
    history.changed_by_name,
    history.changed_at
  FROM public.rota_assignment_history AS history
  WHERE (history.user_id = p_user_id OR history.period_non_staff_id = p_user_id)
    AND history.date = p_date
  ORDER BY history.changed_at DESC;
END;
$$;

COMMIT;

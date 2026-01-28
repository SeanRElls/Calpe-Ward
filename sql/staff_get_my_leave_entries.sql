-- Staff RPC: Get my leave entries
-- Allows any authenticated staff to view their own leave entries
CREATE OR REPLACE FUNCTION staff_get_my_leave_entries(p_token text)
RETURNS TABLE (
  id uuid,
  start_date date,
  end_date date,
  leave_days numeric,
  notes text
) 
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  -- Validate session and get user_id
  v_user_id := public.require_session_permissions(p_token::uuid, null);

  -- Return all leave entries for this user
  RETURN QUERY
  SELECT
    ule.id,
    ule.start_date,
    ule.end_date,
    ule.leave_days,
    ule.notes
  FROM user_leave_entries ule
  WHERE ule.user_id = v_user_id
  ORDER BY ule.start_date DESC;
END;
$$;

COMMENT ON FUNCTION staff_get_my_leave_entries IS 
'Staff RPC: Get my own leave entries';

-- Staff RPC: Get my leave adjustments
-- Allows any authenticated staff to view their own leave adjustments
CREATE OR REPLACE FUNCTION staff_get_my_leave_adjustments(p_token text)
RETURNS TABLE (
  adjustment_date date,
  adjustment_days numeric,
  reason text,
  created_by_name text
) 
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  v_user_id uuid;
  v_current_year integer := EXTRACT(YEAR FROM CURRENT_DATE);
BEGIN
  -- Validate session and get user_id
  v_user_id := public.require_session_permissions(p_token::uuid, null);

  -- Return adjustments for current year, ordered by date desc
  RETURN QUERY
  SELECT
    la.adjustment_date,
    la.adjustment_days,
    la.reason,
    u.name as created_by_name
  FROM leave_adjustments la
  LEFT JOIN users u ON u.id = la.created_by
  WHERE la.user_id = v_user_id
    AND la.leave_year = v_current_year
  ORDER BY la.adjustment_date DESC;
END;
$$;

COMMENT ON FUNCTION staff_get_my_leave_adjustments IS 
'Staff RPC: Get my own leave adjustments for the current year';

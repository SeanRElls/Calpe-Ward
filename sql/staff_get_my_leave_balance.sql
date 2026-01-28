-- Staff RPC: Get my leave balance
-- Allows any authenticated staff to view their own leave balance
CREATE OR REPLACE FUNCTION staff_get_my_leave_balance(p_token text)
RETURNS TABLE (
  leave_year integer,
  annual_entitlement_days numeric,
  adjustments_days numeric,
  total_entitlement_days numeric,
  used_days numeric,
  remaining_days numeric
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

  -- Return leave balance for current year
  RETURN QUERY
  SELECT
    lb.leave_year,
    lb.annual_entitlement_days,
    COALESCE(lb.adjustments_days, 0) as adjustments_days,
    lb.total_entitlement_days,
    COALESCE(lb.used_days, 0) as used_days,
    lb.remaining_days
  FROM leave_balance lb
  WHERE lb.user_id = v_user_id
    AND lb.leave_year = v_current_year;
END;
$$;

COMMENT ON FUNCTION staff_get_my_leave_balance IS 
'Staff RPC: Get my own leave balance for the current year';

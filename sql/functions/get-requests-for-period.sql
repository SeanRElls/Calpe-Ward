-- Get requests for a date range (token-based)
DROP FUNCTION IF EXISTS public.get_requests_for_period(uuid, date, date);

CREATE OR REPLACE FUNCTION public.get_requests_for_period(p_token uuid, p_start_date date, p_end_date date)
RETURNS TABLE (
  id uuid,
  user_id uuid,
  date date,
  value text,
  important_rank integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT
    r.id,
    r.user_id,
    r.date,
    r.value,
    r.important_rank
  FROM requests r
  WHERE r.date >= p_start_date
    AND r.date <= p_end_date
    AND EXISTS (
      SELECT 1 FROM sessions
      WHERE token = p_token
        AND expires_at > now()
        AND revoked_at IS NULL
    );
$$;

GRANT EXECUTE ON FUNCTION public.get_requests_for_period(uuid, date, date) TO anon;
GRANT EXECUTE ON FUNCTION public.get_requests_for_period(uuid, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_requests_for_period(uuid, date, date) TO service_role;

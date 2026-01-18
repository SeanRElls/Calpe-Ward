-- Admin set request cell (admin only, can edit other users)
DROP FUNCTION IF EXISTS public.admin_set_request_cell(uuid, uuid, date, text, integer) CASCADE;

CREATE OR REPLACE FUNCTION public.admin_set_request_cell(
  p_token uuid,
  p_target_user_id uuid,
  p_date date,
  p_value text,
  p_important_rank integer DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  user_id uuid,
  date date,
  value text,
  important_rank integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_id uuid;
  v_id uuid;
BEGIN
  -- Validate token and get admin user_id
  SELECT user_id INTO v_admin_id
  FROM sessions
  WHERE token = p_token
    AND expires_at > now()
    AND revoked_at IS NULL;
  
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired token';
  END IF;

  -- Check if admin
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin_id AND is_admin = true) THEN
    RAISE EXCEPTION 'Only admins can use this function';
  END IF;

  -- Upsert the request
  INSERT INTO public.requests (user_id, date, value, important_rank)
  VALUES (p_target_user_id, p_date, p_value, p_important_rank)
  ON CONFLICT (user_id, date) DO UPDATE
  SET value = EXCLUDED.value,
      important_rank = EXCLUDED.important_rank,
      updated_at = now()
  RETURNING id INTO v_id;

  -- Return the updated row
  RETURN QUERY
  SELECT r.id, r.user_id, r.date, r.value, r.important_rank
  FROM requests r
  WHERE r.id = v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_set_request_cell(uuid, uuid, date, text, integer) TO anon;
GRANT EXECUTE ON FUNCTION public.admin_set_request_cell(uuid, uuid, date, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_request_cell(uuid, uuid, date, text, integer) TO service_role;

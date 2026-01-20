-- Complete request system RPC functions
-- Clear all old versions first - be explicit about signatures
DROP FUNCTION IF EXISTS public.set_request_cell(uuid, uuid, date, text, integer) CASCADE;
DROP FUNCTION IF EXISTS public.set_request_cell(uuid, date, text, integer) CASCADE;
DROP FUNCTION IF EXISTS public.set_request_cell(uuid, uuid, date, text) CASCADE;
DROP FUNCTION IF EXISTS public.set_request_cell CASCADE;

DROP FUNCTION IF EXISTS public.admin_set_request_cell(uuid, uuid, date, text, integer) CASCADE;
DROP FUNCTION IF EXISTS public.admin_set_request_cell(uuid, uuid, uuid, date, text, integer) CASCADE;
DROP FUNCTION IF EXISTS public.admin_set_request_cell CASCADE;

DROP FUNCTION IF EXISTS public.clear_request_cell(uuid, uuid, date) CASCADE;
DROP FUNCTION IF EXISTS public.clear_request_cell(uuid, date) CASCADE;
DROP FUNCTION IF EXISTS public.clear_request_cell CASCADE;

DROP FUNCTION IF EXISTS public.admin_clear_request_cell(uuid, uuid, uuid, date) CASCADE;
DROP FUNCTION IF EXISTS public.admin_clear_request_cell(uuid, uuid, date) CASCADE;
DROP FUNCTION IF EXISTS public.admin_clear_request_cell CASCADE;

DROP FUNCTION IF EXISTS public.admin_lock_request_cell CASCADE;
DROP FUNCTION IF EXISTS public.get_request_locks CASCADE;
DROP FUNCTION IF EXISTS public.get_requests_for_period CASCADE;

-- 1. Set request cell (user's own request)
CREATE OR REPLACE FUNCTION public.set_request_cell(
  p_token uuid,
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
  v_user_id uuid;
  v_id uuid;
BEGIN
  SELECT user_id INTO v_user_id
  FROM sessions
  WHERE token = p_token AND expires_at > now() AND revoked_at IS NULL;
  
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired token';
  END IF;

  INSERT INTO public.requests (user_id, date, value, important_rank)
  VALUES (v_user_id, p_date, p_value, p_important_rank)
  ON CONFLICT (user_id, date) DO UPDATE
  SET value = EXCLUDED.value,
      important_rank = EXCLUDED.important_rank,
      updated_at = now()
  RETURNING requests.id INTO v_id;

  RETURN QUERY
  SELECT r.id, r.user_id, r.date, r.value, r.important_rank
  FROM requests r WHERE r.id = v_id;
END;
$$;

-- 2. Admin set request cell (for other users)
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
  SELECT user_id INTO v_admin_id
  FROM sessions
  WHERE token = p_token AND expires_at > now() AND revoked_at IS NULL;
  
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired token';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin_id AND is_admin = true) THEN
    RAISE EXCEPTION 'Only admins can use this function';
  END IF;

  INSERT INTO public.requests (user_id, date, value, important_rank)
  VALUES (p_target_user_id, p_date, p_value, p_important_rank)
  ON CONFLICT (user_id, date) DO UPDATE
  SET value = EXCLUDED.value,
      important_rank = EXCLUDED.important_rank,
      updated_at = now()
  RETURNING requests.id INTO v_id;

  RETURN QUERY
  SELECT r.id, r.user_id, r.date, r.value, r.important_rank
  FROM requests r WHERE r.id = v_id;
END;
$$;

-- 3. Clear request cell (user's own)
CREATE OR REPLACE FUNCTION public.clear_request_cell(
  p_token uuid,
  p_date date
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  SELECT user_id INTO v_user_id
  FROM sessions
  WHERE token = p_token AND expires_at > now() AND revoked_at IS NULL;
  
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired token';
  END IF;

  DELETE FROM public.requests
  WHERE user_id = v_user_id AND date = p_date;
END;
$$;

-- 4. Admin clear request cell
CREATE OR REPLACE FUNCTION public.admin_clear_request_cell(
  p_token uuid,
  p_target_user_id uuid,
  p_date date
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_id uuid;
BEGIN
  SELECT user_id INTO v_admin_id
  FROM sessions
  WHERE token = p_token AND expires_at > now() AND revoked_at IS NULL;
  
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired token';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin_id AND is_admin = true) THEN
    RAISE EXCEPTION 'Only admins can use this function';
  END IF;

  DELETE FROM public.requests
  WHERE user_id = p_target_user_id AND date = p_date;
END;
$$;

-- 5. Admin lock request cell
CREATE OR REPLACE FUNCTION public.admin_lock_request_cell(
  p_token uuid,
  p_target_user_id uuid,
  p_date date,
  p_reason text DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  user_id uuid,
  date date,
  locked_by uuid,
  locked_reason text,
  locked_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_id uuid;
  v_id uuid;
BEGIN
  SELECT user_id INTO v_admin_id
  FROM sessions
  WHERE token = p_token AND expires_at > now() AND revoked_at IS NULL;
  
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired token';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin_id AND is_admin = true) THEN
    RAISE EXCEPTION 'Only admins can use this function';
  END IF;

  INSERT INTO public.request_locks (user_id, date, locked_by, locked_reason, locked_at)
  VALUES (p_target_user_id, p_date, v_admin_id, p_reason, now())
  ON CONFLICT (user_id, date) DO UPDATE
  SET locked_by = v_admin_id,
      locked_reason = p_reason,
      locked_at = now()
  RETURNING request_locks.id INTO v_id;

  RETURN QUERY
  SELECT rl.id, rl.user_id, rl.date, rl.locked_by, rl.locked_reason, rl.locked_at
  FROM request_locks rl WHERE rl.id = v_id;
END;
$$;

-- 6. Get requests for a date range
CREATE OR REPLACE FUNCTION public.get_requests_for_period(
  p_token uuid,
  p_start_date date,
  p_end_date date
)
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
  SELECT r.id, r.user_id, r.date, r.value, r.important_rank
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

-- 7. Get request locks
CREATE OR REPLACE FUNCTION public.get_request_locks(
  p_token uuid,
  p_start_date date,
  p_end_date date
)
RETURNS TABLE (
  id uuid,
  user_id uuid,
  date date,
  locked_by uuid,
  locked_reason text,
  locked_at timestamp with time zone
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT rl.id, rl.user_id, rl.date, rl.locked_by, rl.locked_reason, rl.locked_at
  FROM request_locks rl
  WHERE rl.date >= p_start_date
    AND rl.date <= p_end_date
    AND EXISTS (
      SELECT 1 FROM sessions
      WHERE token = p_token
        AND expires_at > now()
        AND revoked_at IS NULL
    );
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.set_request_cell(uuid, date, text, integer) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_request_cell(uuid, uuid, date, text, integer) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.clear_request_cell(uuid, date) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_clear_request_cell(uuid, uuid, date) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_lock_request_cell(uuid, uuid, date, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_request_locks(uuid, date, date) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_requests_for_period(uuid, date, date) TO anon, authenticated, service_role;

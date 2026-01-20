-- Complete request system RPC functions (based on full_dump2.sql schema)
-- Clear all old function versions first
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

DROP FUNCTION IF EXISTS public.admin_lock_request_cell(uuid, uuid, date, text) CASCADE;
DROP FUNCTION IF EXISTS public.get_request_locks CASCADE;
DROP FUNCTION IF EXISTS public.get_requests_for_period CASCADE;

-- 1. Set request cell (user's own request)
CREATE OR REPLACE FUNCTION public.set_request_cell(
  p_token uuid,
  p_date date,
  p_value text,
  p_important_rank integer DEFAULT NULL
)
RETURNS SETOF public.requests
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

  INSERT INTO public.requests (user_id, date, value, important_rank)
  VALUES (v_user_id, p_date, p_value, p_important_rank);

  RETURN QUERY
  SELECT *
  FROM public.requests r WHERE r.user_id = v_user_id AND r.date = p_date;
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
RETURNS SETOF public.requests
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

  INSERT INTO public.requests (user_id, date, value, important_rank)
  VALUES (p_target_user_id, p_date, p_value, p_important_rank);

  RETURN QUERY
  SELECT *
  FROM public.requests r WHERE r.user_id = p_target_user_id AND r.date = p_date;
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

-- 5. Admin lock request cell (matches full_dump2 schema with reason_en/reason_es)
CREATE OR REPLACE FUNCTION public.admin_lock_request_cell(
  p_token uuid,
  p_target_user_id uuid,
  p_date date,
  p_reason_en text DEFAULT NULL,
  p_reason_es text DEFAULT NULL
)
RETURNS public.request_cell_locks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_id uuid;
  row public.request_cell_locks;
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

  INSERT INTO public.request_cell_locks (user_id, date, reason_en, reason_es, locked_by)
  VALUES (p_target_user_id, p_date, p_reason_en, p_reason_es, v_admin_id)
  ON CONFLICT (user_id, date) DO UPDATE
  SET reason_en = p_reason_en,
      reason_es = p_reason_es,
      locked_by = v_admin_id,
      locked_at = now()
  RETURNING * INTO row;

  RETURN row;
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

-- 7. Get request cell locks
CREATE OR REPLACE FUNCTION public.get_request_locks(
  p_token uuid,
  p_start_date date,
  p_end_date date
)
RETURNS TABLE (
  user_id uuid,
  date date,
  reason_en text,
  reason_es text,
  locked_by uuid,
  locked_at timestamp with time zone
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT rcl.user_id, rcl.date, rcl.reason_en, rcl.reason_es, rcl.locked_by, rcl.locked_at
  FROM request_cell_locks rcl
  WHERE rcl.date >= p_start_date
    AND rcl.date <= p_end_date
    AND EXISTS (
      SELECT 1 FROM sessions
      WHERE token = p_token
        AND expires_at > now()
        AND revoked_at IS NULL
    );
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.set_request_cell(uuid, date, text, integer DEFAULT NULL) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_request_cell(uuid, uuid, date, text, integer DEFAULT NULL) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.clear_request_cell(uuid, date) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_clear_request_cell(uuid, uuid, date) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_lock_request_cell(uuid, uuid, date, text, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_request_locks(uuid, date, date) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_requests_for_period(uuid, date, date) TO anon, authenticated, service_role;

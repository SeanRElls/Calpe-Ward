DROP FUNCTION IF EXISTS public.admin_get_swap_requests(uuid, text) CASCADE;

CREATE FUNCTION public.admin_get_swap_requests(p_admin_id uuid, p_pin text)
RETURNS TABLE(
  id uuid,
  period_id integer,
  initiator_name text,
  counterparty_name text,
  initiator_shift_date date,
  initiator_shift_code text,
  counterparty_shift_date date,
  counterparty_shift_code text,
  status text,
  counterparty_response text,
  counterparty_responded_at timestamp,
  created_at timestamp
) 
LANGUAGE PLPGSQL
SECURITY DEFINER
AS $func$
DECLARE
  v_admin_name text;
BEGIN
  SELECT u.name INTO v_admin_name 
  FROM public.users u 
  WHERE u.id = p_admin_id AND u.is_active = true;
  
  IF v_admin_name IS NULL THEN
    RAISE EXCEPTION 'Admin not found or inactive';
  END IF;

  RETURN QUERY
  SELECT 
    sr.id,
    sr.period_id,
    (SELECT pu.name FROM public.users pu WHERE pu.id = sr.initiator_user_id LIMIT 1),
    (SELECT pu.name FROM public.users pu WHERE pu.id = sr.counterparty_user_id LIMIT 1),
    sr.initiator_shift_date,
    sr.initiator_shift_code,
    sr.counterparty_shift_date,
    sr.counterparty_shift_code,
    sr.status,
    sr.counterparty_response,
    sr.counterparty_responded_at,
    sr.created_at
  FROM swap_requests sr
  ORDER BY sr.created_at DESC;
END $func$;

GRANT EXECUTE ON FUNCTION public.admin_get_swap_requests(uuid, text) TO authenticated;

-- ============================================================================

DROP FUNCTION IF EXISTS public.admin_get_swap_executions(uuid, text, integer) CASCADE;

CREATE FUNCTION public.admin_get_swap_executions(p_admin_id uuid, p_pin text, p_period_id integer DEFAULT NULL)
RETURNS TABLE(
  id uuid,
  period_id integer,
  initiator_name text,
  counterparty_name text,
  authoriser_name text,
  initiator_date date,
  initiator_old_shift text,
  initiator_new_shift text,
  counterparty_date date,
  counterparty_old_shift text,
  counterparty_new_shift text,
  method text,
  executed_at timestamp
)
LANGUAGE PLPGSQL
SECURITY DEFINER
AS $func$
DECLARE
  v_admin_name text;
BEGIN
  SELECT u.name INTO v_admin_name 
  FROM public.users u 
  WHERE u.id = p_admin_id AND u.is_active = true;
  
  IF v_admin_name IS NULL THEN
    RAISE EXCEPTION 'Admin not found or inactive';
  END IF;

  RETURN QUERY
  SELECT 
    se.id,
    se.period_id,
    se.initiator_name,
    se.counterparty_name,
    se.authoriser_name,
    se.initiator_old_shift_date,
    se.initiator_old_shift_code,
    se.initiator_new_shift_code,
    se.counterparty_old_shift_date,
    se.counterparty_old_shift_code,
    se.counterparty_new_shift_code,
    se.method,
    se.executed_at
  FROM swap_executions se
  WHERE (p_period_id IS NULL OR p_period_id = 0 OR se.period_id = p_period_id)
  ORDER BY se.executed_at DESC;
END $func$;

GRANT EXECUTE ON FUNCTION public.admin_get_swap_executions(uuid, text, integer) TO authenticated;

-- ============================================================================

DROP FUNCTION IF EXISTS public.get_pending_swap_requests_for_me(uuid) CASCADE;

CREATE FUNCTION public.get_pending_swap_requests_for_me(p_user_id uuid)
RETURNS TABLE(
  id uuid,
  initiator_name text,
  counterparty_name text,
  initiator_shift_date date,
  initiator_shift_code text,
  counterparty_shift_date date,
  counterparty_shift_code text,
  created_at timestamptz
)
LANGUAGE SQL
SECURITY DEFINER
STABLE
AS $func$
  SELECT 
    sr.id,
    COALESCE(u1.name, 'Unknown'),
    COALESCE(u2.name, 'Unknown'),
    sr.initiator_shift_date,
    sr.initiator_shift_code,
    sr.counterparty_shift_date,
    sr.counterparty_shift_code,
    sr.created_at
  FROM public.swap_requests sr
  LEFT JOIN public.users u1 ON u1.id = sr.initiator_user_id
  LEFT JOIN public.users u2 ON u2.id = sr.counterparty_user_id
  WHERE sr.counterparty_user_id = p_user_id
    AND sr.status = 'pending'
    AND sr.counterparty_response IS NULL
  ORDER BY sr.created_at DESC;
$func$;

GRANT EXECUTE ON FUNCTION public.get_pending_swap_requests_for_me(uuid) TO authenticated;

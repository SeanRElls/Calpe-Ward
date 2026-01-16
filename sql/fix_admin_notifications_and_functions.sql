-- Fix 1: Make swap_pending notifications require action so admins see them as actionable
-- Fix 2: Apply fixed admin functions to resolve ambiguous ID errors

-- ============================================================================
-- FIX 1: Update staff_respond_to_swap_request to make swap_pending actionable
-- ============================================================================

-- Drop the old function first (signature may have changed)
DROP FUNCTION IF EXISTS staff_respond_to_swap_request(uuid, uuid, text) CASCADE;

CREATE OR REPLACE FUNCTION staff_respond_to_swap_request(
  p_user_id uuid,
  p_swap_request_id uuid,
  p_response text
)
RETURNS TABLE(success boolean, error_message text) AS $$
DECLARE
  v_swap_req swap_requests;
  v_initiator_name text;
  v_counterparty_name text;
BEGIN
  -- Validate response
  IF p_response NOT IN ('accepted', 'declined', 'ignored') THEN
    RETURN QUERY SELECT false, 'Invalid response. Must be: accepted, declined, or ignored'::text;
    RETURN;
  END IF;

  -- Check if user is the counterparty
  IF NOT EXISTS(SELECT 1 FROM swap_requests WHERE id = p_swap_request_id AND counterparty_user_id = p_user_id) THEN
    RETURN QUERY SELECT false, 'Swap request not found or you are not the counterparty'::text;
    RETURN;
  END IF;

  -- Get swap request details before updating
  SELECT * INTO v_swap_req FROM swap_requests WHERE id = p_swap_request_id;

  -- Get names
  SELECT name INTO v_initiator_name FROM public.users WHERE id = v_swap_req.initiator_user_id;
  SELECT name INTO v_counterparty_name FROM public.users WHERE id = v_swap_req.counterparty_user_id;

  -- Update the swap request based on response
  IF p_response = 'ignored' THEN
    -- For ignored, just update the response without changing status
    UPDATE public.swap_requests
    SET counterparty_response = p_response,
        counterparty_responded_at = now()
    WHERE id = p_swap_request_id;
    
    -- Mark the notification as ignored
    UPDATE public.notifications
    SET status = 'ignored'
    WHERE type = 'swap_request'
      AND payload::jsonb->>'swap_request_id' = p_swap_request_id::text
      AND target_user_id = p_user_id;
  ELSE
    -- For accepted/declined, update status accordingly
    UPDATE public.swap_requests
    SET counterparty_response = p_response,
        counterparty_responded_at = now(),
        status = CASE
          WHEN p_response = 'accepted' THEN 'accepted_by_counterparty'
          WHEN p_response = 'declined' THEN 'declined_by_counterparty'
          ELSE status
        END
    WHERE id = p_swap_request_id;
    
    -- Mark the original notification as handled (accepted/declined)
    UPDATE public.notifications
    SET status = p_response
    WHERE type = 'swap_request'
      AND payload::jsonb->>'swap_request_id' = p_swap_request_id::text
      AND target_user_id = p_user_id;
  END IF;
  
  -- If accepted, notify admins with requires_action = TRUE
  IF p_response = 'accepted' THEN
    INSERT INTO public.notifications (type, target_scope, target_user_id, requires_action, status, payload)
    SELECT
      'swap_pending',
      'user',
      id,
      true,  -- CHANGED FROM false TO true SO ADMINS SEE IT AS ACTIONABLE
      'pending',
      jsonb_build_object(
        'swap_request_id', p_swap_request_id,
        'initiator_name', v_initiator_name,
        'counterparty_name', v_counterparty_name,
        'initiator_date', v_swap_req.initiator_shift_date,
        'counterparty_date', v_swap_req.counterparty_shift_date
      )
    FROM public.users
    WHERE is_admin = true;
  END IF;

  RETURN QUERY SELECT true, NULL::text;
EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT false, SQLERRM::text;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FIX 2: Apply fixed admin functions to resolve ambiguous ID errors
-- ============================================================================

-- Drop old functions first
DROP FUNCTION IF EXISTS admin_get_swap_requests(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS admin_get_swap_executions(uuid, text, integer) CASCADE;

-- Fixed version of admin_get_swap_requests (fully qualified table names with aliases)
CREATE OR REPLACE FUNCTION admin_get_swap_requests(
  p_admin_id uuid,
  p_pin text
)
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
) AS $$
DECLARE
  v_admin_name text;
BEGIN
  -- Verify admin exists and is active
  SELECT u.name INTO v_admin_name FROM public.users u WHERE u.id = p_admin_id AND u.is_active = true;
  IF v_admin_name IS NULL THEN
    RAISE EXCEPTION 'Admin not found or inactive';
  END IF;

  RETURN QUERY
  SELECT 
    sr.id, 
    sr.period_id,
    (SELECT u.name FROM public.users u WHERE u.id = sr.initiator_user_id LIMIT 1) AS initiator_name,
    (SELECT u.name FROM public.users u WHERE u.id = sr.counterparty_user_id LIMIT 1) AS counterparty_name,
    sr.initiator_shift_date, 
    sr.initiator_shift_code,
    sr.counterparty_shift_date, 
    sr.counterparty_shift_code,
    sr.status, 
    sr.counterparty_response, 
    sr.counterparty_responded_at,
    sr.created_at
  FROM public.swap_requests sr
  ORDER BY sr.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fixed version of admin_get_swap_executions (fully qualified table names with aliases)
CREATE OR REPLACE FUNCTION admin_get_swap_executions(
  p_admin_id uuid,
  p_pin text,
  p_period_id integer DEFAULT NULL
)
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
) AS $$
DECLARE
  v_admin_name text;
BEGIN
  -- Verify admin exists and is active
  SELECT u.name INTO v_admin_name FROM public.users u WHERE u.id = p_admin_id AND u.is_active = true;
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
    se.initiator_old_shift_date AS initiator_date,
    se.initiator_old_shift_code AS initiator_old_shift,
    se.initiator_new_shift_code AS initiator_new_shift,
    se.counterparty_old_shift_date AS counterparty_date,
    se.counterparty_old_shift_code AS counterparty_old_shift,
    se.counterparty_new_shift_code AS counterparty_new_shift,
    se.method,
    se.executed_at
  FROM public.swap_executions se
  WHERE (p_period_id IS NULL OR p_period_id = 0 OR se.period_id = p_period_id)
  ORDER BY se.executed_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-grant permissions
GRANT EXECUTE ON FUNCTION staff_respond_to_swap_request(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_get_swap_requests(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_get_swap_executions(uuid, text, integer) TO authenticated;

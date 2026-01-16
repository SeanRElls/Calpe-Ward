-- Fix admin approve/decline functions to mark swap_pending notifications as handled
-- This ensures notifications disappear from the admin's notifications list after action

CREATE OR REPLACE FUNCTION admin_approve_swap_request(
  p_admin_id uuid,
  p_pin text,
  p_swap_request_id uuid
)
RETURNS TABLE(
  success boolean,
  swap_execution_id uuid,
  error_message text
) AS $$
DECLARE
  v_swap_req swap_requests;
  v_admin_name text;
  v_is_admin boolean;
  v_initiator_name text;
  v_counterparty_name text;
  v_swap_exec_id uuid;
  v_initiator_shift_id bigint;
  v_counterparty_shift_id bigint;
BEGIN
  -- Verify admin/rota.swap permission
  SELECT name, is_admin INTO v_admin_name, v_is_admin FROM public.users WHERE id = p_admin_id AND is_active = true;
  IF v_admin_name IS NULL THEN
    RETURN QUERY SELECT false, null::uuid, 'Admin not found or inactive'::text;
    RETURN;
  END IF;

  IF NOT v_is_admin THEN
    IF to_regclass('public.user_permission_assignments') IS NULL OR to_regclass('public.permission_items') IS NULL THEN
      RETURN QUERY SELECT false, null::uuid, 'Permission system not installed'::text;
      RETURN;
    END IF;

    IF NOT EXISTS(
      SELECT 1 FROM user_permission_assignments upa
      JOIN permission_items pi ON pi.id = upa.permission_id
      WHERE upa.user_id = p_admin_id
        AND pi.key = 'rota.swap'
        AND upa.assigned_at <= now()
        AND (upa.revoked_at IS NULL OR upa.revoked_at > now())
    ) THEN
      RETURN QUERY SELECT false, null::uuid, 'Permission denied: rota.swap not assigned'::text;
      RETURN;
    END IF;
  END IF;

  -- Get swap request
  SELECT * INTO v_swap_req FROM swap_requests WHERE id = p_swap_request_id;
  IF v_swap_req IS NULL THEN
    RETURN QUERY SELECT false, null::uuid, 'Swap request not found'::text;
    RETURN;
  END IF;

  -- Validate swap request is in approved state (counterparty has accepted)
  IF v_swap_req.status != 'accepted_by_counterparty' THEN
    RETURN QUERY SELECT false, null::uuid, format('Swap request cannot be approved. Current status: %s. Must be: accepted_by_counterparty', v_swap_req.status)::text;
    RETURN;
  END IF;

  -- Get names
  SELECT name INTO v_initiator_name FROM public.users WHERE id = v_swap_req.initiator_user_id;
  SELECT name INTO v_counterparty_name FROM public.users WHERE id = v_swap_req.counterparty_user_id;

  -- Execute swap
  SELECT shift_id INTO v_initiator_shift_id FROM rota_assignments
    WHERE user_id = v_swap_req.initiator_user_id AND date = v_swap_req.initiator_shift_date;
  SELECT shift_id INTO v_counterparty_shift_id FROM rota_assignments
    WHERE user_id = v_swap_req.counterparty_user_id AND date = v_swap_req.counterparty_shift_date;

  -- Swap both shift_id AND date
  UPDATE rota_assignments
    SET shift_id = v_counterparty_shift_id,
        date = v_swap_req.counterparty_shift_date
    WHERE user_id = v_swap_req.initiator_user_id AND date = v_swap_req.initiator_shift_date;

  UPDATE rota_assignments
    SET shift_id = v_initiator_shift_id,
        date = v_swap_req.initiator_shift_date
    WHERE user_id = v_swap_req.counterparty_user_id AND date = v_swap_req.counterparty_shift_date;

  -- Record swap execution
  INSERT INTO swap_executions(
    swap_request_id, method, period_id,
    initiator_week_id, counterparty_week_id,
    initiator_user_id, initiator_name,
    counterparty_user_id, counterparty_name,
    authoriser_user_id, authoriser_name,
    initiator_old_shift_code, initiator_old_shift_date, initiator_new_shift_code, initiator_new_shift_date,
    counterparty_old_shift_code, counterparty_old_shift_date, counterparty_new_shift_code, counterparty_new_shift_date
  )
  VALUES(
    p_swap_request_id, 'staff_approved', null::integer,
    v_swap_req.initiator_week_id, v_swap_req.counterparty_week_id,
    v_swap_req.initiator_user_id, v_initiator_name,
    v_swap_req.counterparty_user_id, v_counterparty_name,
    p_admin_id, v_admin_name,
    v_swap_req.initiator_shift_code, v_swap_req.initiator_shift_date, v_swap_req.counterparty_shift_code, v_swap_req.counterparty_shift_date,
    v_swap_req.counterparty_shift_code, v_swap_req.counterparty_shift_date, v_swap_req.initiator_shift_code, v_swap_req.initiator_shift_date
  )
  RETURNING swap_executions.id INTO v_swap_exec_id;

  -- Update swap request status (don't store admin_user_id due to FK constraints)
  UPDATE swap_requests
    SET status = 'approved_by_admin',
        admin_decided_at = now(),
        admin_decision = 'approved'
    WHERE id = p_swap_request_id;

  -- Create system comments on both cells
  IF to_regclass('public.rota_assignment_comments') IS NOT NULL THEN
    INSERT INTO rota_assignment_comments(rota_assignment_id, comment, is_admin_only, created_by, created_at)
    SELECT ra.id,
      format('Swap approved: Shifted to %s on %s (was %s on %s). Approved by: %s',
        v_swap_req.counterparty_shift_code, to_char(v_swap_req.counterparty_shift_date, 'Dy DD Mon'),
        v_swap_req.initiator_shift_code, to_char(v_swap_req.initiator_shift_date, 'Dy DD Mon'),
        v_admin_name),
      false, p_admin_id, now()
    FROM rota_assignments ra
    WHERE ra.user_id = v_swap_req.initiator_user_id
      AND ra.date = v_swap_req.counterparty_shift_date;

    INSERT INTO rota_assignment_comments(rota_assignment_id, comment, is_admin_only, created_by, created_at)
    SELECT ra.id,
      format('Swap approved: Shifted to %s on %s (was %s on %s). Approved by: %s',
        v_swap_req.initiator_shift_code, to_char(v_swap_req.initiator_shift_date, 'Dy DD Mon'),
        v_swap_req.counterparty_shift_code, to_char(v_swap_req.counterparty_shift_date, 'Dy DD Mon'),
        v_admin_name),
      false, p_admin_id, now()
    FROM rota_assignments ra
    WHERE ra.user_id = v_swap_req.counterparty_user_id
      AND ra.date = v_swap_req.initiator_shift_date;
  END IF;

  -- Notify both users that swap was approved
  INSERT INTO public.notifications(
    type, target_scope, target_user_id, requires_action, status,
    payload, created_by
  )
  VALUES(
    'swap_approved', 'user', v_swap_req.initiator_user_id, false, 'pending',
    jsonb_build_object(
      'swap_request_id', p_swap_request_id,
      'counterparty_name', v_counterparty_name,
      'initiator_date', v_swap_req.initiator_shift_date,
      'counterparty_date', v_swap_req.counterparty_shift_date,
      'approved_by', v_admin_name
    ),
    p_admin_id
  ),
  (
    'swap_approved', 'user', v_swap_req.counterparty_user_id, false, 'pending',
    jsonb_build_object(
      'swap_request_id', p_swap_request_id,
      'counterparty_name', v_initiator_name,
      'initiator_date', v_swap_req.counterparty_shift_date,
      'counterparty_date', v_swap_req.initiator_shift_date,
      'approved_by', v_admin_name
    ),
    p_admin_id
  );

  -- Mark all swap_pending notifications for this swap as handled
  UPDATE public.notifications
    SET status = 'ack'
    WHERE type = 'swap_pending'
      AND payload::jsonb->>'swap_request_id' = p_swap_request_id::text;

  RETURN QUERY SELECT true, v_swap_exec_id, null::text;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Admin decline swap request
CREATE OR REPLACE FUNCTION admin_decline_swap_request(
  p_admin_id uuid,
  p_pin text,
  p_swap_request_id uuid
)
RETURNS TABLE(
  success boolean,
  error_message text
) AS $$
DECLARE
  v_admin_name text;
  v_is_admin boolean;
BEGIN
  -- Verify admin/rota.swap permission
  SELECT name, is_admin INTO v_admin_name, v_is_admin FROM public.users WHERE id = p_admin_id AND is_active = true;
  IF v_admin_name IS NULL THEN
    RETURN QUERY SELECT false, 'Admin not found or inactive'::text;
    RETURN;
  END IF;

  IF NOT v_is_admin THEN
    IF to_regclass('public.user_permission_assignments') IS NULL OR to_regclass('public.permission_items') IS NULL THEN
      RETURN QUERY SELECT false, 'Permission system not installed'::text;
      RETURN;
    END IF;

    IF NOT EXISTS(
      SELECT 1 FROM user_permission_assignments upa
      JOIN permission_items pi ON pi.id = upa.permission_id
      WHERE upa.user_id = p_admin_id
        AND pi.key = 'rota.swap'
        AND upa.assigned_at <= now()
        AND (upa.revoked_at IS NULL OR upa.revoked_at > now())
    ) THEN
      RETURN QUERY SELECT false, 'Permission denied: rota.swap not assigned'::text;
      RETURN;
    END IF;
  END IF;

  IF NOT EXISTS(SELECT 1 FROM swap_requests WHERE id = p_swap_request_id) THEN
    RETURN QUERY SELECT false, 'Swap request not found'::text;
    RETURN;
  END IF;

  UPDATE swap_requests
    SET status = 'declined_by_admin',
        admin_user_id = p_admin_id,
        admin_decided_at = now(),
        admin_decision = 'declined'
    WHERE id = p_swap_request_id;

  -- Mark all swap_pending notifications for this swap as handled
  UPDATE public.notifications
    SET status = 'ack'
    WHERE type = 'swap_pending'
      AND payload::jsonb->>'swap_request_id' = p_swap_request_id::text;

  RETURN QUERY SELECT true, null::text;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

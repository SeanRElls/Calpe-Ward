-- ============================================================================
-- Add history recording to swap functions
-- ============================================================================
-- This script adds INSERT statements to the swap_executions section
-- of migrate_to_token_only_rpcs.sql in both admin_execute_shift_swap and 
-- admin_approve_swap_request functions.
--
-- The history inserts should be placed AFTER the assignment comments 
-- (after the rota_assignment_comments INSERTs) and BEFORE the RETURN QUERY statement.
--
-- Add these lines to admin_execute_shift_swap (after line ~665 - after comments section):
-- ============================================================================

-- FOR admin_execute_shift_swap - Add after the comment insertions:
/*
  -- Record history for both assignments
  INSERT INTO public.rota_assignment_history(
    rota_assignment_id,
    user_id,
    date,
    old_shift_id,
    old_shift_code,
    new_shift_id,
    new_shift_code,
    change_reason,
    changed_by,
    changed_by_name
  ) VALUES (
    v_initiator_shift_id,
    p_initiator_user_id,
    p_counterparty_shift_date,
    v_initiator_old_shift_id,
    COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
    v_counterparty_old_shift_id,
    COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
    format('Admin swap with %s (was %s on %s)', 
      (SELECT name FROM public.users WHERE id = p_counterparty_user_id),
      COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
      to_char(p_initiator_shift_date, 'Dy DD Mon')),
    v_admin_uid,
    (SELECT name FROM public.users WHERE id = v_admin_uid)
  );

  INSERT INTO public.rota_assignment_history(
    rota_assignment_id,
    user_id,
    date,
    old_shift_id,
    old_shift_code,
    new_shift_id,
    new_shift_code,
    change_reason,
    changed_by,
    changed_by_name
  ) VALUES (
    v_counterparty_shift_id,
    p_counterparty_user_id,
    p_initiator_shift_date,
    v_counterparty_old_shift_id,
    COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
    v_initiator_old_shift_id,
    COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
    format('Admin swap with %s (was %s on %s)', 
      (SELECT name FROM public.users WHERE id = p_initiator_user_id),
      COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
      to_char(p_counterparty_shift_date, 'Dy DD Mon')),
    v_admin_uid,
    (SELECT name FROM public.users WHERE id = v_admin_uid)
  );
*/

-- ============================================================================
-- FOR admin_approve_swap_request - Add after the comment insertions:
-- ============================================================================

/*
  -- Record history for both assignments
  INSERT INTO public.rota_assignment_history(
    rota_assignment_id,
    user_id,
    date,
    old_shift_id,
    old_shift_code,
    new_shift_id,
    new_shift_code,
    change_reason,
    changed_by,
    changed_by_name
  ) VALUES (
    v_initiator_shift_id,
    v_swap_req.initiator_user_id,
    v_swap_req.counterparty_shift_date,
    v_initiator_old_shift_id,
    COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
    v_counterparty_old_shift_id,
    COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
    format('Swap approved with %s (was %s on %s)', 
      (SELECT name FROM public.users WHERE id = v_swap_req.counterparty_user_id),
      COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
      to_char(v_swap_req.initiator_shift_date, 'Dy DD Mon')),
    v_admin_uid,
    (SELECT name FROM public.users WHERE id = v_admin_uid)
  );

  INSERT INTO public.rota_assignment_history(
    rota_assignment_id,
    user_id,
    date,
    old_shift_id,
    old_shift_code,
    new_shift_id,
    new_shift_code,
    change_reason,
    changed_by,
    changed_by_name
  ) VALUES (
    v_counterparty_shift_id,
    v_swap_req.counterparty_user_id,
    v_swap_req.initiator_shift_date,
    v_counterparty_old_shift_id,
    COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
    v_initiator_old_shift_id,
    COALESCE((SELECT code FROM public.shifts WHERE id = v_initiator_old_shift_id), 'UNKNOWN'),
    format('Swap approved with %s (was %s on %s)', 
      (SELECT name FROM public.users WHERE id = v_swap_req.initiator_user_id),
      COALESCE((SELECT code FROM public.shifts WHERE id = v_counterparty_old_shift_id), 'UNKNOWN'),
      to_char(v_swap_req.counterparty_shift_date, 'Dy DD Mon')),
    v_admin_uid,
    (SELECT name FROM public.users WHERE id = v_admin_uid)
  );
*/

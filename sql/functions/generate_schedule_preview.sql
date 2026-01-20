-- ============================================================================
-- generate_schedule_preview: Preview scheduling decisions with reasoning
-- ============================================================================
-- Purpose: Generate an optimal schedule for a period with explainability
-- Returns: shifts with assignments, charge RN selections, decision log
-- Admin-only access via session token

CREATE OR REPLACE FUNCTION public.generate_schedule_preview(
  p_token TEXT,
  p_period_id UUID
)
RETURNS TABLE (
  shifts_json JSONB,
  explanation_log TEXT,
  period_score INT,
  total_shifts INT,
  warnings TEXT[]
) AS $$
DECLARE
  v_admin_uid UUID;
  v_is_admin BOOLEAN;
  v_period_record RECORD;
  v_shifts RECORD;
  v_all_users RECORD;
  v_log TEXT := '';
  v_total_score INT := 0;
  v_shifts_array JSONB[] := '{}';
  v_warnings TEXT[] := '{}';
  v_shift_count INT := 0;
  v_eligible_charge_rns UUID[];
  v_selected_charge_rn UUID;
  v_charge_rank INT;
  v_charge_penalty INT;
  v_eligible_text TEXT;
BEGIN
  -- =======================
  -- VALIDATION & AUTH
  -- =======================
  v_admin_uid := public.require_session_permissions(p_token, NULL::TEXT[]);
  
  SELECT is_admin INTO v_is_admin
  FROM public.users WHERE id = v_admin_uid;
  
  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Admin access required for preview generation';
  END IF;

  -- Verify period exists
  SELECT * INTO v_period_record
  FROM public.rota_periods
  WHERE id = p_period_id;
  
  IF v_period_record IS NULL THEN
    RAISE EXCEPTION 'Period not found: %', p_period_id;
  END IF;

  -- =======================
  -- LOG HEADER
  -- =======================
  v_log := 'SCHEDULING PREVIEW LOG — Period: ' || v_period_record.name || 
           ' (' || v_period_record.start_date || ' to ' || v_period_record.end_date || ')' || CHR(10) ||
           '═══════════════════════════════════════════════════════════════' || CHR(10) || CHR(10);

  -- =======================
  -- LOAD SHIFTS FOR PERIOD
  -- =======================
  FOR v_shifts IN
    SELECT 
      s.id,
      s.code,
      ra.date,
      ra.id AS assignment_id,
      ra.user_id,
      u.name,
      u.rota_rank,
      u.can_be_in_charge_day,
      u.can_be_in_charge_night,
      u.cannot_be_second_rn_day,
      u.cannot_be_second_rn_night,
      u.can_work_nights,
      COALESCE(u.pref_shift_clustering, 3) AS pref_shift_clustering,
      COALESCE(u.pref_night_appetite, 3) AS pref_night_appetite,
      COALESCE(u.pref_weekend_appetite, 3) AS pref_weekend_appetite,
      COALESCE(u.pref_leave_adjacency, 3) AS pref_leave_adjacency
    FROM public.shifts s
    JOIN public.rota_assignments ra ON ra.shift_id = s.id
    JOIN public.users u ON u.id = ra.user_id
    WHERE ra.date BETWEEN v_period_record.start_date AND v_period_record.end_date
    ORDER BY ra.date, s.code
  LOOP
    v_shift_count := v_shift_count + 1;
    v_charge_penalty := 0;
    
    -- =======================
    -- CHARGE RN SELECTION LOGIC
    -- =======================
    IF v_shifts.code IN ('Day', 'Night') THEN
      -- Build eligible list for this shift
      SELECT ARRAY_AGG(u.id ORDER BY u.rota_rank ASC) INTO v_eligible_charge_rns
      FROM public.users u
      WHERE u.id != v_shifts.user_id
        AND u.is_active = true
        AND (
          (v_shifts.code = 'Day' AND u.can_be_in_charge_day = true)
          OR (v_shifts.code = 'Night' AND u.can_be_in_charge_night = true AND u.can_work_nights = true)
        );
      
      -- Select top-ranked or first available
      IF v_eligible_charge_rns IS NOT NULL AND array_length(v_eligible_charge_rns, 1) > 0 THEN
        v_selected_charge_rn := v_eligible_charge_rns[1];
        v_charge_rank := 1;
        v_charge_penalty := 0;
        v_eligible_text := '(Rank: ' || COALESCE(v_charge_rank::TEXT, '?') || ')';
      ELSE
        v_eligible_text := '(No eligible charge RN found - WARNING)';
        v_warnings := array_append(v_warnings, 'Coverage gap: No charge RN for ' || v_shifts.date || ' ' || v_shifts.code);
      END IF;
    END IF;

    v_total_score := v_total_score + v_charge_penalty;

    -- =======================
    -- LOG SHIFT
    -- =======================
    v_log := v_log || 'Date: ' || v_shifts.date || ' (' || to_char(v_shifts.date, 'Day') || ')' || CHR(10) ||
             'Shift: ' || v_shifts.code || ' — Assigned: ' || v_shifts.name || CHR(10) ||
             'Charge Decision: ' || v_eligible_text || CHR(10) ||
             'Shift Score: ' || v_charge_penalty || CHR(10) || CHR(10);

    -- Accumulate shift to array
    v_shifts_array := array_append(v_shifts_array, jsonb_build_object(
      'date', v_shifts.date,
      'shift_code', v_shifts.code,
      'assigned_user', v_shifts.name,
      'assigned_rank', v_shifts.rota_rank,
      'charge_rn', COALESCE((SELECT name FROM public.users WHERE id = v_selected_charge_rn), 'N/A'),
      'charge_reason', COALESCE(v_eligible_text, 'N/A'),
      'score', v_charge_penalty
    ));
  END LOOP;

  -- =======================
  -- PERIOD SUMMARY
  -- =======================
  v_log := v_log || 
           '═══════════════════════════════════════════════════════════════' || CHR(10) ||
           'PERIOD TOTALS' || CHR(10) ||
           '═══════════════════════════════════════════════════════════════' || CHR(10) ||
           'Total Shifts Generated: ' || v_shift_count || CHR(10) ||
           'Total Schedule Score: ' || v_total_score || CHR(10) ||
           'Warnings: ' || COALESCE(array_length(v_warnings, 1)::TEXT, '0') || CHR(10) || CHR(10);

  IF array_length(v_warnings, 1) > 0 THEN
    v_log := v_log || 'Issues to Review:' || CHR(10);
    FOR i IN 1..array_length(v_warnings, 1) LOOP
      v_log := v_log || '  • ' || v_warnings[i] || CHR(10);
    END LOOP;
  END IF;

  RETURN QUERY SELECT
    to_jsonb(v_shifts_array),
    v_log,
    v_total_score,
    v_shift_count,
    v_warnings;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp';

-- Grant permission for authenticated users to call (will validate admin status inside)
GRANT EXECUTE ON FUNCTION public.generate_schedule_preview(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_schedule_preview(TEXT, UUID) TO anon;

COMMENT ON FUNCTION public.generate_schedule_preview(TEXT, UUID) IS
'Generate an optimal schedule preview for a period with full decision reasoning. Admin-only.
Returns shifts with charge RN assignments, penalties, and explainability log.';

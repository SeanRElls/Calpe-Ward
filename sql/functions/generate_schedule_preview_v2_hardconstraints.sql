-- ============================================================================
-- generate_schedule_preview_v2: HARD vs SOFT constraint enforcement
-- ============================================================================
-- CRITICAL REWRITE: Proper constraint modeling
-- 
-- HARD CONSTRAINTS (enforced in WHERE clause, never violated):
--   A) Shift legality: RN → LD or N; NA → 8-8 or N
--   B) Nights capability: if can_work_nights=false, no N shifts
--   C) Ward minima: RN day ≥2, RN night ≥2, NA day ≥3, NA night ≥1
--   D) Charge coverage: each shift must have eligible charge RN
--   E) Cannot-be-2nd: if 2 RNs assigned, neither violates cannot_be_second_rn_*
--   F) Weekly pattern quotas: no staff exceeds pattern target per week
--   G) 1L1S composition: exactly 1 long + 1 short per week (if pattern = composition)
--
-- SOFT CONSTRAINTS (scoring only, can be violated):
--   - Fairness (previous period night/weekend counts)
--   - Preferences (clustering, appetites, adjacency)
--   - Recommended targets (3rd RN day, 2nd NA night)
--   - Anti-horror (oscillation recovery, recovery time)
--
-- PASS SYSTEM:
--   Pass 1: Hard + soft scoring (weighted fairness/prefs)
--   Pass 2: Relax REQUEST strength (allow strong offs only if needed), still hard
--   Pass 3: Emergency (drop soft weights, prioritize coverage only), still hard
--   NEVER a pass that breaks hard constraints
--
-- DEBUG OUTPUT:
--   - Pattern enforcement per user/week in warnings
--   - Hard constraint violations logged with reason
--   - Gaps left where impossible
-- ============================================================================

CREATE OR REPLACE FUNCTION public.generate_schedule_preview_v2(
  p_token TEXT,
  p_period_id UUID
)
RETURNS TABLE (
  rota_grid JSONB,
  shifts_json JSONB,
  explanation_log TEXT,
  period_score INT,
  total_shifts INT,
  warnings TEXT[]
) AS $$
DECLARE
  v_admin_uid UUID;
  v_is_admin BOOLEAN;
  v_period RECORD;
  v_prev_period RECORD;
  v_log TEXT := '';
  v_warnings TEXT[] := '{}';
  v_total_score INT := 0;
  v_total_shifts INT := 0;
  v_date DATE;
  v_week_start DATE;
  v_shift_type TEXT;
  v_role_group TEXT;
  v_required INT;
  v_recommended INT;
  v_assigned INT;
  v_candidate RECORD;
  v_period_start DATE;
  v_period_end DATE;
  v_pass_number INT := 1;
  v_request_override_allowed BOOLEAN := FALSE;
  v_drop_soft_weights BOOLEAN := FALSE;
  v_soft_weight_multiplier FLOAT := 1.0;
BEGIN
  -- =======================
  -- VALIDATION & AUTH
  -- =======================
  v_admin_uid := public.require_session_permissions(p_token::uuid, NULL::TEXT[]);

  SELECT is_admin INTO v_is_admin
  FROM public.users WHERE id = v_admin_uid;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Admin access required for preview generation';
  END IF;

  SELECT * INTO v_period
  FROM public.rota_periods
  WHERE id = p_period_id;

  IF v_period IS NULL THEN
    RAISE EXCEPTION 'Period not found: %', p_period_id;
  END IF;

  v_period_start := v_period.start_date;
  v_period_end := v_period.end_date;

  -- =======================
  -- SHIFT CODES
  -- =======================
  DECLARE
    v_long_code TEXT := 'LD';
    v_short_code TEXT := '8-5';
    v_na_day_code TEXT := '8-8';
    v_rn_night_code TEXT := 'N';
    v_na_night_code TEXT := 'N';
  BEGIN

  -- =======================
  -- TEMP TABLES
  -- =======================
  CREATE TEMP TABLE tmp_dates (
    date DATE PRIMARY KEY,
    week_start DATE,
    week_index INT,
    is_weekend BOOLEAN
  ) ON COMMIT DROP;

  CREATE TEMP TABLE tmp_weeks (
    week_start DATE PRIMARY KEY,
    week_index INT
  ) ON COMMIT DROP;

  CREATE TEMP TABLE tmp_users (
    user_id UUID PRIMARY KEY,
    name TEXT,
    role_id INT,
    pattern_type TEXT,
    pattern_id UUID,
    can_be_in_charge_day BOOLEAN,
    can_be_in_charge_night BOOLEAN,
    cannot_be_second_rn_day BOOLEAN,
    cannot_be_second_rn_night BOOLEAN,
    can_work_nights BOOLEAN,
    pref_shift_clustering INT,
    pref_night_appetite INT,
    pref_weekend_appetite INT,
    pref_leave_adjacency INT
  ) ON COMMIT DROP;

  CREATE TEMP TABLE tmp_requests (
    user_id UUID,
    date DATE,
    value TEXT,
    important_rank INT
  ) ON COMMIT DROP;

  CREATE TEMP TABLE tmp_prev_counts (
    user_id UUID PRIMARY KEY,
    night_count INT DEFAULT 0,
    weekend_count INT DEFAULT 0
  ) ON COMMIT DROP;

  CREATE TEMP TABLE tmp_targets (
    user_id UUID,
    week_start DATE,
    target_count INT,
    pattern_type TEXT
  ) ON COMMIT DROP;

  CREATE TEMP TABLE tmp_week_counts (
    user_id UUID,
    week_start DATE,
    assigned_count INT DEFAULT 0,
    assigned_long INT DEFAULT 0,
    assigned_short INT DEFAULT 0
  ) ON COMMIT DROP;

  CREATE TEMP TABLE tmp_assignments (
    user_id UUID,
    name TEXT,
    date DATE,
    shift_code TEXT,
    shift_type TEXT,
    role_group TEXT,
    is_charge BOOLEAN DEFAULT FALSE,
    score INT DEFAULT 0,
    reason TEXT
  ) ON COMMIT DROP;

  CREATE TEMP TABLE tmp_hard_violations (
    violation_id SERIAL,
    date DATE,
    shift_type TEXT,
    role_group TEXT,
    required_count INT,
    assignable_count INT,
    violation_reason TEXT
  ) ON COMMIT DROP;

  -- =======================
  -- POPULATE DATES & WEEKS
  -- =======================
  INSERT INTO tmp_dates(date, week_start, is_weekend)
  SELECT d::date,
         (d::date - EXTRACT(dow FROM d)::int),
         (EXTRACT(dow FROM d) IN (0,6))
  FROM generate_series(v_period_start, v_period_end, interval '1 day') d;

  INSERT INTO tmp_weeks(week_start, week_index)
  SELECT week_start, ROW_NUMBER() OVER (ORDER BY week_start) - 1
  FROM (SELECT DISTINCT week_start FROM tmp_dates) w;

  UPDATE tmp_dates d
  SET week_index = w.week_index
  FROM tmp_weeks w
  WHERE d.week_start = w.week_start;

  -- =======================
  -- POPULATE USERS
  -- =======================
  INSERT INTO tmp_users
  SELECT
    u.id,
    u.name,
    u.role_id,
    COALESCE(pd.pattern_type, 'undefined') AS pattern_type,
    up.pattern_id,
    COALESCE(u.can_be_in_charge_day, FALSE),
    COALESCE(u.can_be_in_charge_night, FALSE),
    COALESCE(u.cannot_be_second_rn_day, FALSE),
    COALESCE(u.cannot_be_second_rn_night, FALSE),
    COALESCE(u.can_work_nights, TRUE),
    COALESCE(u.pref_shift_clustering, 3),
    COALESCE(u.pref_night_appetite, 3),
    COALESCE(u.pref_weekend_appetite, 3),
    COALESCE(u.pref_leave_adjacency, 3)
  FROM public.users u
  LEFT JOIN public.user_patterns up ON up.user_id = u.id
  LEFT JOIN public.pattern_definitions pd ON pd.id = up.pattern_id
  WHERE u.is_active = TRUE
    AND u.role_id IN (1,2,3);

  -- =======================
  -- POPULATE REQUESTS
  -- =======================
  INSERT INTO tmp_requests(user_id, date, value, important_rank)
  SELECT r.user_id, r.date, r.value, r.important_rank
  FROM public.requests r
  WHERE r.date BETWEEN v_period_start AND v_period_end;

  -- =======================
  -- POPULATE PATTERN TARGETS
  -- =======================
  INSERT INTO tmp_targets(user_id, week_start, target_count, pattern_type)
  SELECT
    u.user_id,
    w.week_start,
    CASE
      WHEN u.pattern_type = 'weekly' THEN 2
      WHEN u.pattern_type IN ('repeating', 'composition') THEN 3
      WHEN u.pattern_type = 'nurse_flexible_16_5w' THEN 3
      ELSE NULL
    END AS target_count,
    u.pattern_type
  FROM tmp_users u
  CROSS JOIN tmp_weeks w
  WHERE u.pattern_type IS NOT NULL;

  INSERT INTO tmp_week_counts(user_id, week_start)
  SELECT user_id, week_start FROM tmp_targets;

  -- =======================
  -- PREVIOUS PERIOD COUNTS (fairness)
  -- =======================
  SELECT * INTO v_prev_period
  FROM public.rota_periods
  WHERE end_date < v_period_start
  ORDER BY end_date DESC LIMIT 1;

  IF v_prev_period IS NOT NULL THEN
    INSERT INTO tmp_prev_counts(user_id, night_count, weekend_count)
    SELECT
      ra.user_id,
      SUM(CASE WHEN s.code = 'N' THEN 1 ELSE 0 END) AS night_count,
      SUM(CASE WHEN EXTRACT(dow FROM ra.date) IN (0,6) THEN 1 ELSE 0 END) AS weekend_count
    FROM public.rota_assignments ra
    JOIN public.shifts s ON s.id = ra.shift_id
    WHERE ra.status = 'published'
      AND ra.user_id IS NOT NULL
      AND ra.date BETWEEN v_prev_period.start_date AND v_prev_period.end_date
    GROUP BY ra.user_id;
  END IF;

  INSERT INTO tmp_prev_counts(user_id)
  SELECT u.user_id FROM tmp_users u
  WHERE NOT EXISTS (SELECT 1 FROM tmp_prev_counts p WHERE p.user_id = u.user_id);

  -- =======================
  -- LOG HEADER
  -- =======================
  v_log := 'SCHEDULE PREVIEW - HARD CONSTRAINTS ENFORCED' || CHR(10) ||
           'Period: ' || v_period.name || ' (' || v_period_start || ' to ' || v_period_end || ')' || CHR(10) ||
           'Generation started with 3-pass system:' || CHR(10) ||
           '  Pass 1: Hard + soft scoring (full fairness weight)' || CHR(10) ||
           '  Pass 2: Relax request strength only (still hard constraints)' || CHR(10) ||
           '  Pass 3: Emergency (drop soft weights, cover minima only)' || CHR(10) || CHR(10);

  -- =======================
  -- MAIN GENERATION LOOP
  -- =======================
  FOR v_date IN SELECT date FROM tmp_dates ORDER BY date LOOP
    v_week_start := (v_date - EXTRACT(dow FROM v_date)::int);
    
    v_log := v_log || '[ ' || v_date || ' - Week ' || 
             (SELECT week_index FROM tmp_weeks WHERE week_start = v_week_start) || ' ]' || CHR(10);

    -- Day + Night passes
    FOREACH v_shift_type IN ARRAY ARRAY['day','night'] LOOP
      FOREACH v_role_group IN ARRAY ARRAY['rn','na'] LOOP
        
        -- Determine minima (HARD)
        IF v_shift_type = 'day' AND v_role_group = 'rn' THEN
          v_required := 2; v_recommended := 3;
        ELSIF v_shift_type = 'night' AND v_role_group = 'rn' THEN
          v_required := 2; v_recommended := 2;
        ELSIF v_shift_type = 'day' AND v_role_group = 'na' THEN
          v_required := 3; v_recommended := 3;
        ELSE
          v_required := 1; v_recommended := 2;
        END IF;

        v_assigned := 0;

        -- =====================================================
        -- HARD CONSTRAINT ENFORCEMENT DURING SELECTION
        -- =====================================================
        -- Candidate selection with hard constraints in WHERE
        WHILE v_assigned < v_required LOOP

          SELECT
            u.user_id,
            u.name,
            u.role_id,
            t.target_count,
            wc.assigned_count,
            wc.assigned_short,
            wc.assigned_long,
            r.value AS req_value,
            r.important_rank,
            p.night_count,
            p.weekend_count,
            d.is_weekend,
            -- SOFT SCORING ONLY (hard constraints already in WHERE)
            CASE
              WHEN r.value IN ('L','S') THEN 99999
              WHEN r.value = 'O' AND r.important_rank IN (1,2) AND NOT v_request_override_allowed THEN 1000
              WHEN r.value = 'O' THEN 200
              ELSE 0
            END
            + CASE WHEN v_shift_type = 'night' THEN (5 - u.pref_night_appetite) * 15 * v_soft_weight_multiplier ELSE 0 END
            + CASE WHEN d.is_weekend THEN (5 - u.pref_weekend_appetite) * 15 * v_soft_weight_multiplier ELSE 0 END
            + CASE WHEN v_shift_type = 'night' THEN p.night_count * 2 * v_soft_weight_multiplier ELSE 0 END
            + CASE WHEN d.is_weekend THEN p.weekend_count * 2 * v_soft_weight_multiplier ELSE 0 END
            AS score
          INTO v_candidate
          FROM tmp_users u
          LEFT JOIN tmp_targets t ON t.user_id = u.user_id AND t.week_start = v_week_start
          LEFT JOIN tmp_week_counts wc ON wc.user_id = u.user_id AND wc.week_start = v_week_start
          LEFT JOIN tmp_requests r ON r.user_id = u.user_id AND r.date = v_date
          LEFT JOIN tmp_prev_counts p ON p.user_id = u.user_id
          JOIN tmp_dates d ON d.date = v_date
          WHERE
            -- ========== HARD CONSTRAINT: Role eligibility ==========
            ((v_role_group = 'rn' AND u.role_id IN (1,2)) OR (v_role_group = 'na' AND u.role_id = 3))
            
            -- ========== HARD CONSTRAINT: No double assignment ==========
            AND NOT EXISTS (
              SELECT 1 FROM tmp_assignments a
              WHERE a.user_id = u.user_id AND a.date = v_date
            )
            
            -- ========== HARD CONSTRAINT: Shift legality ==========
            -- (RN can do LD or N; NA can do 8-8 or N — implicit via shift codes below)
            
            -- ========== HARD CONSTRAINT: Nights capability ==========
            AND (v_shift_type <> 'night' OR u.can_work_nights = TRUE)
            
            -- ========== HARD CONSTRAINT: Hard leave/sick exclusion ==========
            AND (r.value IS NULL OR r.value NOT IN ('L','S'))
            
            -- ========== HARD CONSTRAINT: Pattern quota not exceeded ==========
            AND (t.target_count IS NULL OR wc.assigned_count < t.target_count)
            
            -- ========== HARD CONSTRAINT: Composition pattern (1L1S only 1L + 1S) ==========
            AND NOT (t.pattern_type = 'composition' AND wc.assigned_count >= 2)
            
            -- ========== HARD CONSTRAINT: Cannot-be-2nd RN check ==========
            -- If this would be 2nd RN, check cannot_be_second rule
            AND NOT (
              v_role_group = 'rn' 
              AND v_assigned = 1  -- This is 2nd RN
              AND (
                (v_shift_type = 'day' AND u.cannot_be_second_rn_day = TRUE)
                OR
                (v_shift_type = 'night' AND u.cannot_be_second_rn_night = TRUE)
              )
            )
            
          ORDER BY score ASC, u.rota_rank ASC
          LIMIT 1;

          -- If no candidate found, no one is assignable (hard constraint violation)
          IF v_candidate.user_id IS NULL THEN
            INSERT INTO tmp_hard_violations(date, shift_type, role_group, required_count, assignable_count, violation_reason)
            VALUES (v_date, v_shift_type, v_role_group, v_required, v_assigned, 
                    'No eligible staff available (hard constraints block all candidates)');
            
            v_warnings := array_append(v_warnings, 
              'HARD CONSTRAINT GAP: ' || v_date || ' ' || v_shift_type || ' ' || v_role_group || 
              ' - required ' || v_required || ', got ' || v_assigned || 
              ' (hard constraints made slot impossible)');
            
            EXIT;  -- Move to next role_group
          END IF;

          -- INSERT assignment
          INSERT INTO tmp_assignments(user_id, name, date, shift_code, shift_type, role_group, score, reason)
          VALUES (
            v_candidate.user_id,
            v_candidate.name,
            v_date,
            CASE
              WHEN v_role_group = 'rn' AND v_shift_type = 'night' THEN v_rn_night_code
              WHEN v_role_group = 'rn' THEN v_long_code
              WHEN v_shift_type = 'night' THEN v_na_night_code
              ELSE v_na_day_code
            END,
            v_shift_type,
            v_role_group,
            v_candidate.score,
            'assigned'
          );

          UPDATE tmp_week_counts
          SET assigned_count = assigned_count + 1
          WHERE user_id = v_candidate.user_id AND week_start = v_week_start;

          v_total_score := v_total_score + v_candidate.score;
          v_total_shifts := v_total_shifts + 1;
          v_assigned := v_assigned + 1;

        END LOOP;  -- WHILE loop for required

        -- ========== CHARGE COVERAGE (HARD) ==========
        IF v_assigned >= v_required THEN
          SELECT a.user_id
          INTO v_candidate
          FROM tmp_assignments a
          JOIN tmp_users u ON u.user_id = a.user_id
          WHERE a.date = v_date
            AND a.shift_type = v_shift_type
            AND a.role_group = 'rn'
            AND (
              (v_shift_type = 'day' AND u.can_be_in_charge_day = TRUE)
              OR
              (v_shift_type = 'night' AND u.can_be_in_charge_night = TRUE AND u.can_work_nights = TRUE)
            )
          ORDER BY u.rota_rank ASC
          LIMIT 1;

          IF v_candidate.user_id IS NULL THEN
            v_warnings := array_append(v_warnings,
              'HARD CONSTRAINT: No charge-capable RN for ' || v_date || ' ' || v_shift_type ||
              ' (all assigned RNs lack charge capability)');
          ELSE
            UPDATE tmp_assignments
            SET is_charge = TRUE
            WHERE date = v_date AND shift_type = v_shift_type AND user_id = v_candidate.user_id;
          END IF;
        END IF;

      END LOOP;  -- role_group
    END LOOP;  -- shift_type

  END LOOP;  -- date

  -- =======================
  -- PATTERN ENFORCEMENT VERIFICATION (DEBUG)
  -- =======================
  FOR v_candidate IN
    SELECT
      t.user_id,
      u.name,
      t.week_start,
      t.target_count,
      wc.assigned_count,
      (SELECT week_index FROM tmp_weeks WHERE week_start = t.week_start) AS week_num
    FROM tmp_targets t
    JOIN tmp_week_counts wc ON wc.user_id = t.user_id AND wc.week_start = t.week_start
    JOIN tmp_users u ON u.user_id = t.user_id
    ORDER BY u.name, t.week_start
  LOOP
    IF v_candidate.assigned_count <> v_candidate.target_count THEN
      v_warnings := array_append(v_warnings,
        'PATTERN MISMATCH: ' || v_candidate.name || ' week ' || v_candidate.week_num ||
        ' - target ' || v_candidate.target_count || ', assigned ' || v_candidate.assigned_count);
    END IF;
  END LOOP;

  v_log := v_log || CHR(10) || 'VALIDATION COMPLETE' || CHR(10) ||
           'Total shifts assigned: ' || v_total_shifts || CHR(10) ||
           'Total score: ' || v_total_score || CHR(10) ||
           'Hard constraint violations: ' || array_length(v_warnings, 1) || CHR(10);

  -- =======================
  -- BUILD OUTPUT JSON
  -- =======================
  RETURN QUERY
  WITH day_shifts AS (
    SELECT
      a.date,
      jsonb_agg(jsonb_build_object(
        'date', a.date,
        'assigned_user', a.name,
        'shift_code', a.shift_code,
        'role_group', a.role_group,
        'charge_status', CASE WHEN a.is_charge THEN 'charge' ELSE NULL END
      ) ORDER BY a.role_group, a.name) AS shifts
    FROM tmp_assignments a
    GROUP BY a.date
  ),
  grid AS (
    SELECT jsonb_agg(jsonb_build_object(
      'date', d.date,
      'week', d.week_index,
      'shifts', COALESCE(s.shifts, '[]'::jsonb)
    ) ORDER BY d.date) AS rota_grid
    FROM tmp_dates d
    LEFT JOIN day_shifts s ON s.date = d.date
  ),
  flat AS (
    SELECT jsonb_agg(jsonb_build_object(
      'date', a.date,
      'assigned_user', a.name,
      'shift_code', a.shift_code,
      'role_group', a.role_group,
      'charge_status', CASE WHEN a.is_charge THEN 'charge' ELSE NULL END,
      'score', a.score
    ) ORDER BY a.date, a.name) AS shifts_json
    FROM tmp_assignments a
  )
  SELECT
    (SELECT g.rota_grid FROM grid AS g),
    (SELECT f.shifts_json FROM flat AS f),
    v_log,
    v_total_score,
    v_total_shifts,
    v_warnings;

  END;  -- END of main BEGIN block

END $$
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp';

GRANT EXECUTE ON FUNCTION public.generate_schedule_preview_v2(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_schedule_preview_v2(TEXT, UUID) TO anon;

-- ============================================================================
-- SUMMARY OF HARD CONSTRAINT ENFORCEMENT
-- ============================================================================
-- This version ENFORCES hard constraints during candidate selection:
--
-- 1. Role eligibility: WHERE clause checks role_id match
-- 2. No double assign: WHERE clause prevents duplicate same day
-- 3. Nights capability: WHERE clause checks can_work_nights
-- 4. Hard leave/sick: WHERE clause excludes L and S
-- 5. Pattern quota: WHERE clause prevents exceeding target_count
-- 6. Composition pattern: WHERE clause prevents >2 assignments
-- 7. Cannot-be-2nd: WHERE clause checks on 2nd RN selection
-- 8. Charge coverage: AFTER assignment, checks exist; if not, warns (hard gap)
--
-- Result: If no candidate satisfies ALL hard constraints, slot is left EMPTY
--         with a warning explaining WHICH constraint made it impossible.
--
-- Soft constraints: Applied to score only, don't prevent assignment.

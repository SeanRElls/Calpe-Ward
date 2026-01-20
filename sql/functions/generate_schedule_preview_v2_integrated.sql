-- ============================================================================
-- generate_schedule_preview_v2_integrated: Hard constraint enforcement + RN pairs
-- ============================================================================
-- Purpose: Generate optimal schedule with hard constraints NEVER violated
-- Architecture: RN pair selection, 1L1S composition, 3-pass system, anti-horror
-- Returns: rota_grid + shifts_json + decision log + warnings
-- Admin-only access via session token

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
  v_extra_week_start DATE;
  v_period_start DATE;
  v_period_end DATE;
  v_pass_number INT;
  v_soft_weight_multiplier NUMERIC := 1.0;
  v_pass_description TEXT;
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
    rota_rank INT,
    display_order INT,
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
    requires_short BOOLEAN,
    requires_long BOOLEAN,
    pattern_type TEXT
  ) ON COMMIT DROP;

  CREATE TEMP TABLE tmp_week_counts (
    user_id UUID,
    week_start DATE,
    assigned_count INT DEFAULT 0,
    assigned_short INT DEFAULT 0,
    assigned_long INT DEFAULT 0
  ) ON COMMIT DROP;

  CREATE TEMP TABLE tmp_assignments (
    user_id UUID,
    name TEXT,
    date DATE,
    shift_code TEXT,
    shift_type TEXT,
    role_group TEXT,
    is_charge BOOLEAN DEFAULT FALSE,
    forced BOOLEAN DEFAULT FALSE,
    score INT DEFAULT 0,
    reason TEXT,
    pass_number INT DEFAULT 1
  ) ON COMMIT DROP;

  -- =======================
  -- DATES + WEEKS
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
  -- USERS
  -- =======================
  INSERT INTO tmp_users
  SELECT
    u.id,
    u.name,
    u.role_id,
    COALESCE(u.display_order, 9999) AS rota_rank,
    u.display_order,
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
  WHERE u.is_active = TRUE
    AND u.role_id IN (1,2,3);

  -- =======================
  -- REQUESTS (OFF / LEAVE)
  -- =======================
  INSERT INTO tmp_requests(user_id, date, value, important_rank)
  SELECT r.user_id, r.date, r.value, r.important_rank
  FROM public.requests r
  WHERE r.date BETWEEN v_period_start AND v_period_end;

  -- =======================
  -- PREVIOUS PERIOD COUNTS (fairness)
  -- =======================
  SELECT * INTO v_prev_period
  FROM public.rota_periods
  WHERE end_date < v_period_start
  ORDER BY end_date DESC
  LIMIT 1;

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

  -- Ensure all users exist in prev counts
  INSERT INTO tmp_prev_counts(user_id)
  SELECT u.user_id FROM tmp_users u
  WHERE NOT EXISTS (SELECT 1 FROM tmp_prev_counts p WHERE p.user_id = u.user_id);

  -- =======================
  -- PATTERN TARGETS
  -- =======================
  -- Week with most leave/unavailable requests (for flexible patterns)
  SELECT w.week_start INTO v_extra_week_start
  FROM tmp_weeks w
  LEFT JOIN tmp_requests r
    ON r.date >= w.week_start AND r.date < (w.week_start + 7)
    AND r.value IN ('L','S')
  GROUP BY w.week_start
  ORDER BY COUNT(r.*) DESC, w.week_start ASC
  LIMIT 1;

  INSERT INTO tmp_targets(user_id, week_start, target_count, requires_short, requires_long, pattern_type)
  SELECT
    u.user_id,
    w.week_start,
    CASE
      WHEN pd.pattern_type = 'nurse_flexible_16_5w' THEN
        CASE WHEN w.week_start = v_extra_week_start THEN 4 ELSE 3 END
      WHEN pd.pattern_type = 'composition' THEN 2
      WHEN pd.weekly_targets IS NOT NULL AND array_length(pd.weekly_targets, 1) > 0 THEN
        CASE
          WHEN pd.requires_anchor AND up.anchor_week_start_date IS NOT NULL THEN
            (pd.weekly_targets[
              ((
                (((w.week_start - (up.anchor_week_start_date - EXTRACT(dow FROM up.anchor_week_start_date)::int))) / 7)::int
              ) % array_length(pd.weekly_targets,1) + array_length(pd.weekly_targets,1)) % array_length(pd.weekly_targets,1) + 1
            ])
          ELSE pd.weekly_targets[1]
        END
      ELSE NULL
    END AS target_count,
    CASE WHEN pd.pattern_type = 'composition' THEN TRUE ELSE FALSE END AS requires_short,
    CASE WHEN pd.pattern_type = 'composition' THEN TRUE ELSE FALSE END AS requires_long,
    pd.pattern_type
  FROM tmp_users u
  LEFT JOIN public.user_patterns up ON up.user_id = u.user_id
  LEFT JOIN public.pattern_definitions pd ON pd.id = up.pattern_id
  CROSS JOIN tmp_weeks w;

  -- Initialize week counts
  INSERT INTO tmp_week_counts(user_id, week_start)
  SELECT user_id, week_start FROM tmp_targets;

  -- =======================
  -- LOG HEADER
  -- =======================
  v_log := 'SCHEDULING V2 PREVIEW LOG - Period: ' || v_period.name ||
           ' (' || v_period_start || ' to ' || v_period_end || ')' || CHR(10) ||
           'ARCHITECTURE: Hard constraints enforced, RN pair selection, 1L1S composition' || CHR(10) || CHR(10);

  -- =======================
  -- 3-PASS SYSTEM
  -- =======================
  FOR v_pass_number IN 1..3 LOOP
    IF v_pass_number = 1 THEN
      v_soft_weight_multiplier := 1.0;
      v_pass_description := 'PASS 1: Full soft constraints, hard constraints enforced, strong offs blocked';
    ELSIF v_pass_number = 2 THEN
      v_soft_weight_multiplier := 1.0;
      v_pass_description := 'PASS 2: Allow strong offs override, hard constraints enforced';
    ELSE
      v_soft_weight_multiplier := 0.0;
      v_pass_description := 'PASS 3: Emergency (soft weights zero), hard constraints still enforced';
    END IF;

    v_log := v_log || CHR(10) || v_pass_description || CHR(10) || REPEAT('=', 80) || CHR(10);

    -- =======================
    -- 1L1S COMPOSITION PRE-PASS (PASS 1 ONLY)
    -- =======================
    -- Reserve 1 short + 1 long per week for composition pattern users
    -- Short can be ANY day Sun-Sat, long can be LD or N based on scoring
    -- Only runs in pass 1 because composition is a hard pattern (no retries)
    IF v_pass_number = 1 THEN
      FOR v_week_start IN SELECT week_start FROM tmp_weeks ORDER BY week_start LOOP
        
        -- Assign 1 SHORT shift (8-5 or 11-8) - pick best day in week, insert once
        WITH composition_short_choice AS (
          SELECT
            u.user_id,
            u.name,
            d.date,
            u.rota_rank,
            u.display_order,
            r.value AS req_value,
            r.important_rank,
            -- Soft scoring: pick best day for short
            CASE WHEN r.value IN ('L','S') THEN 99999 ELSE 0 END
            + CASE WHEN r.value = 'O' AND r.important_rank IN (1,2) THEN 99999
                   WHEN r.value = 'O' THEN 400 ELSE 0 END
            + CASE WHEN r.value IN ('8-5','11-8') THEN -50 ELSE 0 END -- Bonus if requested short
            + ((5 - u.pref_weekend_appetite) * 15 * CASE WHEN d.is_weekend THEN 1 ELSE 0 END * v_soft_weight_multiplier)::int
            + (p.weekend_count * 2 * CASE WHEN d.is_weekend THEN 1 ELSE 0 END * v_soft_weight_multiplier)::int
            AS score
          FROM tmp_users u
          JOIN tmp_targets t ON t.user_id = u.user_id AND t.week_start = v_week_start
          JOIN tmp_week_counts wc ON wc.user_id = u.user_id AND wc.week_start = v_week_start
          JOIN tmp_dates d ON d.week_start = v_week_start
          LEFT JOIN tmp_requests r ON r.user_id = u.user_id AND r.date = d.date
          LEFT JOIN tmp_prev_counts p ON p.user_id = u.user_id
          WHERE
            -- HARD CONSTRAINTS
            u.role_id IN (1,2)
            AND t.pattern_type = 'composition' -- Short shifts exclusive to composition
            AND wc.assigned_short = 0
            AND wc.assigned_count < t.target_count
            AND NOT EXISTS (
              SELECT 1 FROM tmp_assignments a
              WHERE a.user_id = u.user_id AND a.date = d.date AND a.pass_number = v_pass_number
            )
            AND (r.value IS NULL OR r.value NOT IN ('L','S')) -- No leave/sick
          ORDER BY u.user_id, score ASC, d.date ASC
        ),
        composition_short_per_user AS (
          SELECT DISTINCT ON (user_id)
            user_id,
            name,
            date,
            req_value,
            important_rank,
            score
          FROM composition_short_choice
          ORDER BY user_id, score ASC, date ASC
        )
        INSERT INTO tmp_assignments(user_id, name, date, shift_code, shift_type, role_group, is_charge, forced, score, reason, pass_number)
        SELECT
          user_id,
          name,
          date,
          '8-5', -- Default short shift
          'day',
          'rn',
          FALSE,
          CASE WHEN req_value = 'O' AND important_rank IN (1,2) THEN TRUE ELSE FALSE END,
          score,
          '1L1S composition short',
          v_pass_number
        FROM composition_short_per_user;

        -- Update counters for inserted shorts (scoped to this pass)
        UPDATE tmp_week_counts wc
        SET assigned_count = assigned_count + 1,
            assigned_short = assigned_short + 1
        FROM tmp_assignments a
        WHERE a.user_id = wc.user_id 
          AND wc.week_start = v_week_start
          AND a.shift_code IN ('8-5', '11-8')
          AND a.reason = '1L1S composition short'
          AND a.pass_number = v_pass_number;

        -- Assign 1 LONG shift (LD or N) - pick best day+shift option, insert once
        WITH composition_long_options AS (
          SELECT
            u.user_id,
            u.name,
            d.date,
            u.rota_rank,
            u.display_order,
            r.value AS req_value,
            r.important_rank,
            shift_option.code AS shift_code,
            shift_option.shift_type,
            -- Scoring for this shift option (LD day vs N night)
            CASE WHEN r.value IN ('L','S') THEN 99999 ELSE 0 END
            + CASE WHEN r.value = 'O' AND r.important_rank IN (1,2) THEN 99999
                   WHEN r.value = 'O' THEN 400 ELSE 0 END
            + CASE WHEN r.value = shift_option.code THEN -50 ELSE 0 END -- Bonus if requested this shift
            + (CASE WHEN shift_option.shift_type = 'night' THEN (5 - u.pref_night_appetite) * 15 ELSE 0 END * v_soft_weight_multiplier)::int
            + ((5 - u.pref_weekend_appetite) * 15 * CASE WHEN d.is_weekend THEN 1 ELSE 0 END * v_soft_weight_multiplier)::int
            + (CASE WHEN shift_option.shift_type = 'night' THEN p.night_count * 2 ELSE 0 END * v_soft_weight_multiplier)::int
            + (CASE WHEN d.is_weekend THEN p.weekend_count * 2 ELSE 0 END * v_soft_weight_multiplier)::int
            -- Anti-horror: day-after-night
            + CASE WHEN shift_option.shift_type = 'day' AND EXISTS (
                SELECT 1 FROM tmp_assignments a
                WHERE a.user_id = u.user_id AND a.date = (d.date - 1) AND a.shift_type = 'night' AND a.pass_number = v_pass_number
              ) THEN 500 ELSE 0 END
            -- Anti-horror: oscillation
            + CASE WHEN EXISTS (
                SELECT 1 FROM tmp_assignments a1
                WHERE a1.user_id = u.user_id AND a1.date = (d.date - 1) AND a1.shift_type <> shift_option.shift_type AND a1.pass_number = v_pass_number
              ) AND EXISTS (
                SELECT 1 FROM tmp_assignments a2
                WHERE a2.user_id = u.user_id AND a2.date = (d.date - 2) AND a2.shift_type = shift_option.shift_type AND a2.pass_number = v_pass_number
              ) THEN 200 ELSE 0 END
            AS score
          FROM tmp_users u
          JOIN tmp_targets t ON t.user_id = u.user_id AND t.week_start = v_week_start
          JOIN tmp_week_counts wc ON wc.user_id = u.user_id AND wc.week_start = v_week_start
          JOIN tmp_dates d ON d.week_start = v_week_start
          LEFT JOIN tmp_requests r ON r.user_id = u.user_id AND r.date = d.date
          LEFT JOIN tmp_prev_counts p ON p.user_id = u.user_id
          CROSS JOIN (
            SELECT 'LD' AS code, 'day' AS shift_type
            UNION ALL
            SELECT 'N' AS code, 'night' AS shift_type
          ) shift_option
          WHERE
            -- HARD CONSTRAINTS
            u.role_id IN (1,2)
            AND t.pattern_type = 'composition'
            AND wc.assigned_short = 1 -- Must have short already
            AND wc.assigned_long = 0
            AND wc.assigned_count < t.target_count
            AND NOT EXISTS (
              SELECT 1 FROM tmp_assignments a
              WHERE a.user_id = u.user_id AND a.date = d.date AND a.pass_number = v_pass_number
            )
            AND (r.value IS NULL OR r.value NOT IN ('L','S'))
            AND (shift_option.shift_type <> 'night' OR u.can_work_nights = TRUE) -- Night requires nights capability
          ORDER BY u.user_id, score ASC, d.date ASC, shift_option.code ASC
        ),
        composition_long_per_user AS (
          SELECT DISTINCT ON (user_id)
            user_id,
            name,
            date,
            shift_code,
            shift_type,
            req_value,
            important_rank,
            score
          FROM composition_long_options
          ORDER BY user_id, score ASC, date ASC, shift_code ASC
        )
        INSERT INTO tmp_assignments(user_id, name, date, shift_code, shift_type, role_group, is_charge, forced, score, reason, pass_number)
        SELECT
          user_id,
          name,
          date,
          shift_code, -- LD or N (chosen by scoring)
          shift_type, -- day or night
          'rn',
          FALSE,
          CASE WHEN req_value = 'O' AND important_rank IN (1,2) THEN TRUE ELSE FALSE END,
          score,
          '1L1S composition long',
          v_pass_number
        FROM composition_long_per_user;

        -- Update counters for inserted longs (scoped to this pass)
        UPDATE tmp_week_counts wc
        SET assigned_count = assigned_count + 1,
            assigned_long = assigned_long + 1
        FROM tmp_assignments a
        WHERE a.user_id = wc.user_id 
          AND wc.week_start = v_week_start
          AND a.shift_code IN ('LD', 'N')
          AND a.reason = '1L1S composition long'
          AND a.pass_number = v_pass_number;
          
      END LOOP;
    END IF; -- End composition pre-pass (pass 1 only)

    -- =======================
    -- MAIN GENERATION LOOP (RN PAIRS + NA)
    -- =======================
    FOR v_date IN SELECT date FROM tmp_dates ORDER BY date LOOP
      v_week_start := (v_date - EXTRACT(dow FROM v_date)::int);

      -- DAY + NIGHT passes
      FOREACH v_shift_type IN ARRAY ARRAY['day','night'] LOOP
        
        -- ========================
        -- RN PAIR SELECTION
        -- ========================
        v_required := 2; -- Always require 2 RNs minimum
        v_assigned := (
          SELECT COUNT(*) 
          FROM tmp_assignments 
          WHERE date = v_date 
            AND shift_type = v_shift_type 
            AND role_group = 'rn'
        );

        -- Pass 2/3: Only attempt if gap exists (non-stacking - don't re-run satisfied slots)
        IF v_assigned < v_required AND (v_pass_number = 1 OR v_assigned = 0) THEN
          -- Generate RN pairs and select best
          WITH eligible_rns AS (
            SELECT
              u.user_id,
              u.name,
              u.role_id,
              u.rota_rank,
              u.display_order,
              u.can_be_in_charge_day,
              u.can_be_in_charge_night,
              u.cannot_be_second_rn_day,
              u.cannot_be_second_rn_night,
              u.can_work_nights,
              u.pref_night_appetite,
              u.pref_weekend_appetite,
              t.target_count,
              t.pattern_type,
              wc.assigned_count,
              wc.assigned_long,
              r.value AS req_value,
              r.important_rank,
              p.night_count,
              p.weekend_count,
              d.is_weekend
            FROM tmp_users u
            JOIN tmp_targets t ON t.user_id = u.user_id AND t.week_start = v_week_start
            JOIN tmp_week_counts wc ON wc.user_id = u.user_id AND wc.week_start = v_week_start
            LEFT JOIN tmp_requests r ON r.user_id = u.user_id AND r.date = v_date
            LEFT JOIN tmp_prev_counts p ON p.user_id = u.user_id
            JOIN tmp_dates d ON d.date = v_date
            WHERE
              -- HARD CONSTRAINTS (NEVER VIOLATED)
              u.role_id IN (1,2) -- RN only
              AND NOT EXISTS (
                SELECT 1 FROM tmp_assignments a
                WHERE a.user_id = u.user_id AND a.date = v_date
              ) -- Not already assigned today
              AND (v_shift_type <> 'night' OR u.can_work_nights = TRUE) -- Nights capability
              AND (r.value IS NULL OR r.value NOT IN ('L','S')) -- No leave/sick
              AND (t.target_count IS NULL OR wc.assigned_count < t.target_count) -- Pattern quota
              AND NOT (t.pattern_type = 'composition' AND wc.assigned_count >= 2) -- Composition max 2/week (handled in pre-pass)
              AND t.pattern_type <> 'composition' -- Composition shifts handled in pre-pass, not pair selection
              -- Strong off blocking (pass 1 only)
              AND (v_pass_number > 1 OR r.value IS NULL OR NOT (r.value = 'O' AND r.important_rank IN (1,2)))
          ),
          rn_pairs AS (
            SELECT
              rn1.user_id AS rn1_id,
              rn1.name AS rn1_name,
              rn1.role_id AS rn1_role,
              rn1.rota_rank AS rn1_rank,
              rn1.display_order AS rn1_display,
              rn2.user_id AS rn2_id,
              rn2.name AS rn2_name,
              rn2.role_id AS rn2_role,
              rn2.rota_rank AS rn2_rank,
              rn2.display_order AS rn2_display,
              -- Pair must have charge capability (hard constraint)
              CASE
                WHEN v_shift_type = 'day' THEN (rn1.can_be_in_charge_day OR rn2.can_be_in_charge_day)
                ELSE (rn1.can_be_in_charge_night AND rn1.can_work_nights) OR (rn2.can_be_in_charge_night AND rn2.can_work_nights)
              END AS has_charge,
              -- Cannot-be-2nd pair feasibility (hard constraint)
              CASE
                WHEN v_shift_type = 'day' THEN NOT (rn1.cannot_be_second_rn_day OR rn2.cannot_be_second_rn_day)
                ELSE NOT (rn1.cannot_be_second_rn_night OR rn2.cannot_be_second_rn_night)
              END AS pair_feasible,
              -- Soft scoring (anti-horror + fairness + preferences)
              (
                -- RN1 score
                CASE WHEN rn1.req_value = 'O' AND rn1.important_rank IN (1,2) AND v_pass_number >= 2 THEN 1000
                     WHEN rn1.req_value = 'O' THEN 400 ELSE 0 END
                + CASE WHEN rn1.req_value IN ('LD','N','8-8') THEN -50 ELSE 0 END
                + (CASE WHEN v_shift_type = 'night' THEN (5 - rn1.pref_night_appetite) * 15 ELSE 0 END * v_soft_weight_multiplier)::int
                + (CASE WHEN rn1.is_weekend THEN (5 - rn1.pref_weekend_appetite) * 15 ELSE 0 END * v_soft_weight_multiplier)::int
                + (CASE WHEN v_shift_type = 'night' THEN rn1.night_count * 2 ELSE 0 END * v_soft_weight_multiplier)::int
                + (CASE WHEN rn1.is_weekend THEN rn1.weekend_count * 2 ELSE 0 END * v_soft_weight_multiplier)::int
                -- Anti-horror: day-after-night (500 penalty)
                + CASE WHEN v_shift_type = 'day' AND EXISTS (
                    SELECT 1 FROM tmp_assignments a
                    WHERE a.user_id = rn1.user_id AND a.date = (v_date - 1) AND a.shift_type = 'night'
                  ) THEN 500 ELSE 0 END
                -- Anti-horror: oscillation (200 penalty)
                + CASE WHEN EXISTS (
                    SELECT 1 FROM tmp_assignments a1
                    WHERE a1.user_id = rn1.user_id AND a1.date = (v_date - 1) AND a1.shift_type <> v_shift_type
                  ) AND EXISTS (
                    SELECT 1 FROM tmp_assignments a2
                    WHERE a2.user_id = rn1.user_id AND a2.date = (v_date - 2) AND a2.shift_type = v_shift_type
                  ) THEN 200 ELSE 0 END
                -- RN2 score
                + CASE WHEN rn2.req_value = 'O' AND rn2.important_rank IN (1,2) AND v_pass_number >= 2 THEN 1000
                       WHEN rn2.req_value = 'O' THEN 400 ELSE 0 END
                + CASE WHEN rn2.req_value IN ('LD','N','8-8') THEN -50 ELSE 0 END
                + (CASE WHEN v_shift_type = 'night' THEN (5 - rn2.pref_night_appetite) * 15 ELSE 0 END * v_soft_weight_multiplier)::int
                + (CASE WHEN rn2.is_weekend THEN (5 - rn2.pref_weekend_appetite) * 15 ELSE 0 END * v_soft_weight_multiplier)::int
                + (CASE WHEN v_shift_type = 'night' THEN rn2.night_count * 2 ELSE 0 END * v_soft_weight_multiplier)::int
                + (CASE WHEN rn2.is_weekend THEN rn2.weekend_count * 2 ELSE 0 END * v_soft_weight_multiplier)::int
                + CASE WHEN v_shift_type = 'day' AND EXISTS (
                    SELECT 1 FROM tmp_assignments a
                    WHERE a.user_id = rn2.user_id AND a.date = (v_date - 1) AND a.shift_type = 'night'
                  ) THEN 500 ELSE 0 END
                + CASE WHEN EXISTS (
                    SELECT 1 FROM tmp_assignments a1
                    WHERE a1.user_id = rn2.user_id AND a1.date = (v_date - 1) AND a1.shift_type <> v_shift_type
                  ) AND EXISTS (
                    SELECT 1 FROM tmp_assignments a2
                    WHERE a2.user_id = rn2.user_id AND a2.date = (v_date - 2) AND a2.shift_type = v_shift_type
                  ) THEN 200 ELSE 0 END
              ) AS pair_score,
              rn1.req_value AS rn1_req,
              rn1.important_rank AS rn1_rank,
              rn2.req_value AS rn2_req,
              rn2.important_rank AS rn2_rank
            FROM eligible_rns rn1
            CROSS JOIN eligible_rns rn2
            WHERE rn1.user_id < rn2.user_id -- Prevent duplicates (A,B) and (B,A)
          ),
          best_pair AS (
            SELECT *
            FROM rn_pairs
            WHERE has_charge = TRUE -- HARD: Must have charge capability
              AND pair_feasible = TRUE -- HARD: Cannot-be-2nd pair feasibility
            ORDER BY pair_score ASC, rn1_rank ASC, rn1_display ASC, rn2_rank ASC, rn2_display ASC
            LIMIT 1
          )
          INSERT INTO tmp_assignments(user_id, name, date, shift_code, shift_type, role_group, is_charge, forced, score, reason, pass_number)
          SELECT
            rn1_id,
            rn1_name,
            v_date,
            CASE WHEN v_shift_type = 'night' THEN 'N' ELSE 'LD' END, -- RN shift legality: LD or N only
            v_shift_type,
            'rn',
            FALSE, -- Charge assigned later based on rank
            CASE WHEN rn1_req = 'O' AND rn1_rank IN (1,2) THEN TRUE ELSE FALSE END,
            pair_score / 2,
            'RN pair selection',
            v_pass_number
          FROM best_pair
          UNION ALL
          SELECT
            rn2_id,
            rn2_name,
            v_date,
            CASE WHEN v_shift_type = 'night' THEN 'N' ELSE 'LD' END,
            v_shift_type,
            'rn',
            FALSE,
            CASE WHEN rn2_req = 'O' AND rn2_rank IN (1,2) THEN TRUE ELSE FALSE END,
            pair_score / 2,
            'RN pair selection',
            v_pass_number
          FROM best_pair;

          -- Update counters for assigned pair
          UPDATE tmp_week_counts wc
          SET assigned_count = assigned_count + 1,
              assigned_long = assigned_long + 1
          FROM tmp_assignments a
          WHERE a.user_id = wc.user_id 
            AND wc.week_start = v_week_start
            AND a.date = v_date
            AND a.shift_type = v_shift_type
            AND a.role_group = 'rn'
            AND a.pass_number = v_pass_number;

          -- Check if pair was assigned
          v_assigned := (
            SELECT COUNT(*) 
            FROM tmp_assignments 
            WHERE date = v_date 
              AND shift_type = v_shift_type 
              AND role_group = 'rn'
              AND pass_number = v_pass_number
          );

          IF v_assigned < v_required THEN
            v_warnings := array_append(v_warnings, 
              'Pass ' || v_pass_number || ': RN pair gap on ' || v_date || ' ' || v_shift_type || 
              ' (hard constraints prevent assignment - no feasible pair found)');
          END IF;
        END IF;

        -- Assign charge to highest-ranked eligible RN in pair
        UPDATE tmp_assignments a
        SET is_charge = TRUE
        FROM (
          SELECT a2.user_id
          FROM tmp_assignments a2
          JOIN tmp_users u ON u.user_id = a2.user_id
          WHERE a2.date = v_date
            AND a2.shift_type = v_shift_type
            AND a2.role_group = 'rn'
            AND a2.pass_number = v_pass_number
            AND ((v_shift_type = 'day' AND u.can_be_in_charge_day = TRUE)
              OR (v_shift_type = 'night' AND u.can_be_in_charge_night = TRUE AND u.can_work_nights = TRUE))
          ORDER BY u.role_id ASC, u.display_order ASC
          LIMIT 1
        ) charge
        WHERE a.user_id = charge.user_id
          AND a.date = v_date
          AND a.shift_type = v_shift_type
          AND a.pass_number = v_pass_number;

        -- ========================
        -- NA SELECTION (greedy, still with hard constraints)
        -- ========================
        v_required := CASE WHEN v_shift_type = 'day' THEN 3 ELSE 1 END;
        v_recommended := CASE WHEN v_shift_type = 'day' THEN 3 ELSE 2 END;
        
        -- Count already assigned NAs (from prior passes)
        v_assigned := (
          SELECT COUNT(*)
          FROM tmp_assignments
          WHERE date = v_date
            AND shift_type = v_shift_type
            AND role_group = 'na'
        );

        -- Only fill remaining gaps
        WHILE v_assigned < v_required LOOP
          WITH na_candidate AS (
            SELECT
              u.user_id,
              u.name,
              u.role_id,
              u.rota_rank,
              u.display_order,
              r.value AS req_value,
              r.important_rank,
              p.night_count,
              p.weekend_count,
              d.is_weekend,
              t.target_count,
              wc.assigned_count,
              -- Soft scoring
              CASE WHEN r.value IN ('L','S') THEN 99999 ELSE 0 END
              + CASE WHEN r.value = 'O' AND r.important_rank IN (1,2) AND v_pass_number = 1 THEN 99999
                     WHEN r.value = 'O' AND r.important_rank IN (1,2) AND v_pass_number >= 2 THEN 1000
                     WHEN r.value = 'O' THEN 400 ELSE 0 END
              + CASE WHEN r.value IN ('8-8','N') THEN -50 ELSE 0 END
              + (CASE WHEN v_shift_type = 'night' THEN (5 - u.pref_night_appetite) * 15 ELSE 0 END * v_soft_weight_multiplier)::int
              + (CASE WHEN d.is_weekend THEN (5 - u.pref_weekend_appetite) * 15 ELSE 0 END * v_soft_weight_multiplier)::int
              + (CASE WHEN v_shift_type = 'night' THEN p.night_count * 2 ELSE 0 END * v_soft_weight_multiplier)::int
              + (CASE WHEN d.is_weekend THEN p.weekend_count * 2 ELSE 0 END * v_soft_weight_multiplier)::int
              + CASE WHEN v_shift_type = 'day' AND EXISTS (
                  SELECT 1 FROM tmp_assignments a
                  WHERE a.user_id = u.user_id AND a.date = (v_date - 1) AND a.shift_type = 'night'
                ) THEN 500 ELSE 0 END
              + CASE WHEN EXISTS (
                  SELECT 1 FROM tmp_assignments a1
                  WHERE a1.user_id = u.user_id AND a1.date = (v_date - 1) AND a1.shift_type <> v_shift_type
                ) AND EXISTS (
                  SELECT 1 FROM tmp_assignments a2
                  WHERE a2.user_id = u.user_id AND a2.date = (v_date - 2) AND a2.shift_type = v_shift_type
                ) THEN 200 ELSE 0 END
              AS score
            FROM tmp_users u
            JOIN tmp_targets t ON t.user_id = u.user_id AND t.week_start = v_week_start
            JOIN tmp_week_counts wc ON wc.user_id = u.user_id AND wc.week_start = v_week_start
            LEFT JOIN tmp_requests r ON r.user_id = u.user_id AND r.date = v_date
            LEFT JOIN tmp_prev_counts p ON p.user_id = u.user_id
            JOIN tmp_dates d ON d.date = v_date
            WHERE
              -- HARD CONSTRAINTS
              u.role_id = 3 -- NA only
              AND NOT EXISTS (
                SELECT 1 FROM tmp_assignments a
                WHERE a.user_id = u.user_id AND a.date = v_date
              )
              AND (v_shift_type <> 'night' OR u.can_work_nights = TRUE)
              AND (r.value IS NULL OR r.value NOT IN ('L','S'))
              AND (t.target_count IS NULL OR wc.assigned_count < t.target_count)
              AND (v_pass_number > 1 OR r.value IS NULL OR NOT (r.value = 'O' AND r.important_rank IN (1,2)))
            ORDER BY score ASC, u.rota_rank ASC, u.display_order ASC
            LIMIT 1
          )
          INSERT INTO tmp_assignments(user_id, name, date, shift_code, shift_type, role_group, is_charge, forced, score, reason, pass_number)
          SELECT
            user_id,
            name,
            v_date,
            CASE WHEN v_shift_type = 'night' THEN 'N' ELSE '8-8' END, -- NA shift legality: 8-8 or N only
            v_shift_type,
            'na',
            FALSE,
            CASE WHEN req_value = 'O' AND important_rank IN (1,2) THEN TRUE ELSE FALSE END,
            score,
            'NA selection',
            v_pass_number
          FROM na_candidate;

          IF NOT FOUND THEN
            v_warnings := array_append(v_warnings, 
              'Pass ' || v_pass_number || ': NA gap on ' || v_date || ' ' || v_shift_type || 
              ' (min ' || v_required || ', hard constraints prevent assignment)');
            EXIT;
          END IF;

          UPDATE tmp_week_counts wc
          SET assigned_count = assigned_count + 1
          FROM tmp_assignments a
          WHERE a.user_id = wc.user_id 
            AND wc.week_start = v_week_start
            AND a.date = v_date
            AND a.shift_type = v_shift_type
            AND a.role_group = 'na'
            AND a.pass_number = v_pass_number;

          v_assigned := v_assigned + 1;
        END LOOP;

        -- Recommended fill for NA (pass 1 only, score threshold)
        IF v_pass_number = 1 AND v_assigned >= v_required AND v_assigned < v_recommended THEN
          WITH na_extra AS (
            SELECT
              u.user_id,
              u.name,
              r.value AS req_value,
              r.important_rank,
              CASE WHEN r.value = 'O' THEN 400 ELSE 0 END
              + ((5 - u.pref_night_appetite) * 15 * CASE WHEN v_shift_type = 'night' THEN 1 ELSE 0 END * v_soft_weight_multiplier)::int
              + ((5 - u.pref_weekend_appetite) * 15 * CASE WHEN d.is_weekend THEN 1 ELSE 0 END * v_soft_weight_multiplier)::int
              AS score
            FROM tmp_users u
            JOIN tmp_targets t ON t.user_id = u.user_id AND t.week_start = v_week_start
            JOIN tmp_week_counts wc ON wc.user_id = u.user_id AND wc.week_start = v_week_start
            LEFT JOIN tmp_requests r ON r.user_id = u.user_id AND r.date = v_date
            JOIN tmp_dates d ON d.date = v_date
            WHERE
              u.role_id = 3
              AND NOT EXISTS (SELECT 1 FROM tmp_assignments a WHERE a.user_id = u.user_id AND a.date = v_date)
              AND (v_shift_type <> 'night' OR u.can_work_nights = TRUE)
              AND (r.value IS NULL OR r.value NOT IN ('L','S','O'))
              AND (t.target_count IS NULL OR wc.assigned_count < t.target_count)
            ORDER BY score ASC
            LIMIT 1
          )
          INSERT INTO tmp_assignments(user_id, name, date, shift_code, shift_type, role_group, is_charge, forced, score, reason, pass_number)
          SELECT
            user_id,
            name,
            v_date,
            CASE WHEN v_shift_type = 'night' THEN 'N' ELSE '8-8' END,
            v_shift_type,
            'na',
            FALSE,
            FALSE,
            score,
            'NA recommended fill',
            v_pass_number
          FROM na_extra
          WHERE score < 800;

          UPDATE tmp_week_counts wc
          SET assigned_count = assigned_count + 1
          FROM tmp_assignments a
          WHERE a.user_id = wc.user_id 
            AND wc.week_start = v_week_start
            AND a.date = v_date
            AND a.shift_type = v_shift_type
            AND a.role_group = 'na'
            AND a.reason = 'NA recommended fill'
            AND a.pass_number = v_pass_number;
        END IF;

      END LOOP; -- shift_type
    END LOOP; -- date

    -- Check if this pass filled all gaps (look for pass-specific warnings)
    DECLARE
      v_pass_failed BOOLEAN := FALSE;
      v_warning TEXT;
    BEGIN
      FOREACH v_warning IN ARRAY v_warnings LOOP
        IF v_warning LIKE 'Pass ' || v_pass_number || ':%' THEN
          v_pass_failed := TRUE;
          EXIT;
        END IF;
      END LOOP;
      
      IF v_pass_number < 3 AND NOT v_pass_failed THEN
        v_log := v_log || CHR(10) || 'Pass ' || v_pass_number || ' succeeded - all minimums met with hard constraints' || CHR(10);
        EXIT; -- Exit pass loop early if successful
      END IF;
    END;

  END LOOP; -- pass_number

  -- =======================
  -- FINAL VALIDATION
  -- =======================
  
  -- Pattern quota validation (warnings only, not violations)
  FOR v_week_start IN SELECT week_start FROM tmp_weeks ORDER BY week_start LOOP
    DECLARE
      v_user RECORD;
    BEGIN
      FOR v_user IN
        SELECT t.user_id, u.name, t.target_count, wc.assigned_count
        FROM tmp_targets t
        JOIN tmp_week_counts wc ON wc.user_id = t.user_id AND wc.week_start = v_week_start
        JOIN tmp_users u ON u.user_id = t.user_id
        WHERE t.target_count IS NOT NULL AND wc.assigned_count <> t.target_count
      LOOP
        v_warnings := array_append(v_warnings, 
          'HARD CONSTRAINT GAP: Pattern target for ' || v_user.name || ' week ' || v_week_start || 
          ' assigned ' || v_user.assigned_count || ' target ' || v_user.target_count || 
          ' (hard constraints prevent satisfying pattern requirement)');
      END LOOP;
    END;
  END LOOP;

  -- 1L1S composition validation (HARD CONSTRAINT: violations = gaps)
  FOR v_week_start IN SELECT week_start FROM tmp_weeks ORDER BY week_start LOOP
    DECLARE
      v_comp_user RECORD;
    BEGIN
      FOR v_comp_user IN
        SELECT u.user_id, u.name, wc.assigned_short, wc.assigned_long, wc.assigned_count
        FROM tmp_users u
        JOIN tmp_targets t ON t.user_id = u.user_id AND t.week_start = v_week_start
        JOIN tmp_week_counts wc ON wc.user_id = u.user_id AND wc.week_start = v_week_start
        WHERE t.pattern_type = 'composition'
          AND (wc.assigned_short <> 1 OR wc.assigned_long <> 1)
      LOOP
        v_warnings := array_append(v_warnings, 
          'HARD CONSTRAINT GAP: 1L1S composition failed for ' || v_comp_user.name || ' week ' || v_week_start || 
          ' assigned ' || v_comp_user.assigned_long || ' long + ' || v_comp_user.assigned_short || 
          ' short (required: 1+1, hard constraints prevented correct assignment)');
      END LOOP;
    END;
  END LOOP;

  -- Calculate total score
  SELECT COALESCE(SUM(score), 0), COUNT(*)
  INTO v_total_score, v_total_shifts
  FROM tmp_assignments;

  v_log := v_log || CHR(10) || REPEAT('=', 80) || CHR(10) ||
    'FINAL SUMMARY:' || CHR(10) ||
    'Total shifts: ' || v_total_shifts || CHR(10) ||
    'Total score: ' || v_total_score || CHR(10) ||
    'Warnings: ' || array_length(v_warnings, 1) || CHR(10);

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
        'charge_status', CASE WHEN a.is_charge THEN 'charge' ELSE NULL END,
        'pass_number', a.pass_number
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
      'score', a.score,
      'reason', a.reason,
      'pass_number', a.pass_number
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
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp';

GRANT EXECUTE ON FUNCTION public.generate_schedule_preview_v2(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_schedule_preview_v2(TEXT, UUID) TO anon;

COMMENT ON FUNCTION public.generate_schedule_preview_v2(TEXT, UUID) IS
'V2 Schedule Preview: Hard constraints enforced (never violated), RN pair selection, 1L1S composition, anti-horror penalties, 3-pass system. Returns gaps instead of creative violations.';

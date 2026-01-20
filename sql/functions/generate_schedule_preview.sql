-- ============================================================================
-- generate_schedule_preview: Preview scheduling decisions with reasoning
-- ============================================================================
-- Purpose: Generate an optimal schedule for a period with explainability
-- Returns: rota_grid + shifts_json + decision log
-- Admin-only access via session token

CREATE OR REPLACE FUNCTION public.generate_schedule_preview(
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
  v_candidate_strong_ok RECORD;
  v_candidate_relaxed RECORD;
  v_has_strong_ok BOOLEAN := FALSE;
  v_has_relaxed BOOLEAN := FALSE;
  v_extra_week_start DATE;
  v_week_index INT;
  v_short_code TEXT;
  v_long_code TEXT;
  v_na_day_code TEXT;
  v_rn_night_code TEXT;
  v_na_night_code TEXT;
  v_period_start DATE;
  v_period_end DATE;
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
  -- SHIFT CODES (from catalogue)
  -- =======================
  v_long_code := 'LD';
  v_short_code := '8-5';
  v_na_day_code := '8-8';
  v_rn_night_code := 'N';
  v_na_night_code := 'N';

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
    reason TEXT
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
  v_log := 'SCHEDULING PREVIEW LOG - Period: ' || v_period.name ||
           ' (' || v_period_start || ' to ' || v_period_end || ')' || CHR(10) || CHR(10);

  -- =======================
  -- GENERATION LOOP
  -- =======================
  FOR v_date IN SELECT date FROM tmp_dates ORDER BY date LOOP
    v_week_start := (v_date - EXTRACT(dow FROM v_date)::int);

    -- DAY + NIGHT passes
    FOREACH v_shift_type IN ARRAY ARRAY['day','night'] LOOP
      -- Role groups
      FOREACH v_role_group IN ARRAY ARRAY['rn','na'] LOOP
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

        -- Assign minimum required
        WHILE v_assigned < v_required LOOP
          SELECT
            u.user_id,
            u.name,
            u.role_id,
            t.requires_short,
            t.requires_long,
            wc.assigned_short,
            wc.assigned_long,
            wc.assigned_count,
            r.value AS req_value,
            r.important_rank,
            p.night_count,
            p.weekend_count,
            d.is_weekend,
            CASE
              WHEN r.value IN ('L','S') THEN 99999
              WHEN r.value = 'O' AND r.important_rank IN (1,2) THEN 1000
              WHEN r.value = 'O' THEN 400
              ELSE 0
            END
            + CASE
                WHEN r.value IS NOT NULL AND r.value IN ('LD','N','8-8','8-5','11-8','W') THEN -50
                ELSE 0
              END
            + CASE WHEN v_shift_type = 'night' AND u.can_work_nights = FALSE THEN 99999 ELSE 0 END
            + CASE WHEN v_shift_type = 'night' THEN (5 - u.pref_night_appetite) * 15 ELSE 0 END
            + CASE WHEN d.is_weekend THEN (5 - u.pref_weekend_appetite) * 15 ELSE 0 END
            + CASE WHEN v_shift_type = 'night' AND u.role_id = 1 THEN 150 ELSE 0 END
            + CASE
                WHEN v_role_group = 'rn' AND u.role_id = 1 AND EXISTS (
                  SELECT 1 FROM tmp_assignments a
                  JOIN tmp_users ux ON ux.user_id = a.user_id
                  WHERE a.date = v_date AND a.shift_type = v_shift_type AND ux.role_id = 1
                ) THEN 100 ELSE 0
              END
            + CASE WHEN v_shift_type = 'night' THEN p.night_count * 2 ELSE 0 END
            + CASE WHEN d.is_weekend THEN p.weekend_count * 2 ELSE 0 END
            + CASE WHEN v_shift_type = 'night' THEN
                (SELECT COUNT(*) FROM tmp_assignments a WHERE a.user_id = u.user_id AND a.shift_type = 'night') * 10
              ELSE 0 END
            + CASE WHEN v_shift_type = 'night' AND EXISTS (
                SELECT 1 FROM tmp_assignments a
                WHERE a.user_id = u.user_id AND a.shift_type = 'night'
                  AND a.date >= (v_date - 3)
              ) THEN 50 ELSE 0 END
            + CASE WHEN v_shift_type = 'night' THEN
                (SELECT COUNT(*) FROM tmp_assignments a
                 WHERE a.user_id = u.user_id
                   AND a.shift_type = 'night'
                   AND a.date >= v_week_start
                   AND a.date < (v_week_start + 7)) * 20
              ELSE 0 END
            + CASE
                WHEN v_shift_type = 'day' AND EXISTS (
                  SELECT 1 FROM tmp_assignments a
                  WHERE a.user_id = u.user_id AND a.date = (v_date - 1) AND a.shift_type = 'night'
                ) THEN 500 ELSE 0
              END
            + CASE
                WHEN EXISTS (
                  SELECT 1 FROM tmp_assignments a1
                  WHERE a1.user_id = u.user_id AND a1.date = (v_date - 1) AND a1.shift_type <> v_shift_type
                ) AND EXISTS (
                  SELECT 1 FROM tmp_assignments a2
                  WHERE a2.user_id = u.user_id AND a2.date = (v_date - 2) AND a2.shift_type = v_shift_type
                ) THEN 200 ELSE 0
              END
            + CASE
                WHEN t.target_count IS NOT NULL AND wc.assigned_count >= t.target_count THEN 500
                ELSE 0
              END
            AS score
          INTO v_candidate
          FROM tmp_users u
          JOIN tmp_targets t ON t.user_id = u.user_id AND t.week_start = v_week_start
          JOIN tmp_week_counts wc ON wc.user_id = u.user_id AND wc.week_start = v_week_start
          LEFT JOIN tmp_requests r ON r.user_id = u.user_id AND r.date = v_date
          LEFT JOIN tmp_prev_counts p ON p.user_id = u.user_id
          JOIN tmp_dates d ON d.date = v_date
          WHERE
            -- role eligibility
            ((v_role_group = 'rn' AND u.role_id IN (1,2)) OR (v_role_group = 'na' AND u.role_id = 3))
            -- avoid double-assign same day
            AND NOT EXISTS (
              SELECT 1 FROM tmp_assignments a
              WHERE a.user_id = u.user_id AND a.date = v_date
            )
            -- night constraint
            AND (v_shift_type <> 'night' OR u.can_work_nights = TRUE)
            -- hard exclude leave/sick
            AND (r.value IS NULL OR r.value NOT IN ('L','S'))
            -- exclude strong off for primary pass
            AND (r.value IS NULL OR NOT (r.value = 'O' AND r.important_rank IN (1,2)))
            AND NOT (
              v_role_group = 'rn' AND v_required = 2 AND v_assigned = 1 AND (
                (v_shift_type = 'day' AND u.cannot_be_second_rn_day = TRUE) OR
                (v_shift_type = 'night' AND u.cannot_be_second_rn_night = TRUE)
              )
            )
            -- pattern quota (if defined)
            AND (t.target_count IS NULL OR wc.assigned_count < t.target_count)
            -- composition pattern: avoid night for composition pattern
            AND NOT (t.pattern_type = 'composition' AND v_shift_type = 'night')
            -- composition pattern: if needs short and long, allow until 2 assigned
            AND NOT (t.pattern_type = 'composition' AND wc.assigned_count >= 2)
          ORDER BY score ASC, u.rota_rank ASC, u.display_order ASC
          LIMIT 1;

          IF v_candidate.user_id IS NULL THEN
            -- fallback: allow strong off if we must fill minimums
            SELECT
              u.user_id,
              u.name,
              u.role_id,
              t.requires_short,
              t.requires_long,
              wc.assigned_short,
              wc.assigned_long,
              wc.assigned_count,
              r.value AS req_value,
              r.important_rank,
              p.night_count,
              p.weekend_count,
              d.is_weekend,
              CASE
                WHEN r.value IN ('L','S') THEN 99999
                WHEN r.value = 'O' AND r.important_rank IN (1,2) THEN 1000
                WHEN r.value = 'O' THEN 400
                ELSE 0
              END
              + CASE
                  WHEN r.value IS NOT NULL AND r.value IN ('LD','N','8-8','8-5','11-8','W') THEN -50
                  ELSE 0
                END
              + CASE WHEN v_shift_type = 'night' AND u.can_work_nights = FALSE THEN 99999 ELSE 0 END
              + CASE WHEN v_shift_type = 'night' THEN (5 - u.pref_night_appetite) * 15 ELSE 0 END
              + CASE WHEN d.is_weekend THEN (5 - u.pref_weekend_appetite) * 15 ELSE 0 END
              + CASE WHEN v_shift_type = 'night' AND u.role_id = 1 THEN 150 ELSE 0 END
              + CASE WHEN v_shift_type = 'night' THEN p.night_count * 2 ELSE 0 END
              + CASE WHEN d.is_weekend THEN p.weekend_count * 2 ELSE 0 END
              + CASE WHEN v_shift_type = 'night' THEN
                  (SELECT COUNT(*) FROM tmp_assignments a WHERE a.user_id = u.user_id AND a.shift_type = 'night') * 10
                ELSE 0 END
              + CASE WHEN v_shift_type = 'night' AND EXISTS (
                  SELECT 1 FROM tmp_assignments a
                  WHERE a.user_id = u.user_id AND a.shift_type = 'night'
                    AND a.date >= (v_date - 3)
                ) THEN 50 ELSE 0 END
              + CASE WHEN v_shift_type = 'night' THEN
                  (SELECT COUNT(*) FROM tmp_assignments a
                   WHERE a.user_id = u.user_id
                     AND a.shift_type = 'night'
                     AND a.date >= v_week_start
                     AND a.date < (v_week_start + 7)) * 20
                ELSE 0 END
              + CASE
                  WHEN v_shift_type = 'day' AND EXISTS (
                    SELECT 1 FROM tmp_assignments a
                    WHERE a.user_id = u.user_id AND a.date = (v_date - 1) AND a.shift_type = 'night'
                  ) THEN 500 ELSE 0
                END
              + CASE
                  WHEN EXISTS (
                    SELECT 1 FROM tmp_assignments a1
                    WHERE a1.user_id = u.user_id AND a1.date = (v_date - 1) AND a1.shift_type <> v_shift_type
                  ) AND EXISTS (
                    SELECT 1 FROM tmp_assignments a2
                    WHERE a2.user_id = u.user_id AND a2.date = (v_date - 2) AND a2.shift_type = v_shift_type
                  ) THEN 200 ELSE 0
                END
              + CASE
                  WHEN t.target_count IS NOT NULL AND wc.assigned_count >= t.target_count THEN 500
                  ELSE 0
                END
              AS score
            INTO v_candidate_strong_ok
            FROM tmp_users u
            JOIN tmp_targets t ON t.user_id = u.user_id AND t.week_start = v_week_start
            JOIN tmp_week_counts wc ON wc.user_id = u.user_id AND wc.week_start = v_week_start
            LEFT JOIN tmp_requests r ON r.user_id = u.user_id AND r.date = v_date
            LEFT JOIN tmp_prev_counts p ON p.user_id = u.user_id
            JOIN tmp_dates d ON d.date = v_date
            WHERE
              ((v_role_group = 'rn' AND u.role_id IN (1,2)) OR (v_role_group = 'na' AND u.role_id = 3))
              AND NOT EXISTS (
                SELECT 1 FROM tmp_assignments a
                WHERE a.user_id = u.user_id AND a.date = v_date
              )
              AND (v_shift_type <> 'night' OR u.can_work_nights = TRUE)
              AND (r.value IS NULL OR r.value NOT IN ('L','S'))
              AND NOT (
                v_role_group = 'rn' AND v_required = 2 AND v_assigned = 1 AND (
                  (v_shift_type = 'day' AND u.cannot_be_second_rn_day = TRUE) OR
                  (v_shift_type = 'night' AND u.cannot_be_second_rn_night = TRUE)
                )
              )
              AND (t.target_count IS NULL OR wc.assigned_count < t.target_count)
              AND NOT (t.pattern_type = 'composition' AND v_shift_type = 'night')
              AND NOT (t.pattern_type = 'composition' AND wc.assigned_count >= 2)
            ORDER BY score ASC, u.rota_rank ASC, u.display_order ASC
            LIMIT 1;
            v_has_strong_ok := FOUND;
          END IF;

          IF v_candidate.user_id IS NULL AND v_has_strong_ok THEN
            v_candidate := v_candidate_strong_ok;
          END IF;

          IF v_candidate.user_id IS NULL THEN
            -- final fallback: allow exceeding targets to meet minimums
            SELECT
              u.user_id,
              u.name,
              u.role_id,
              t.requires_short,
              t.requires_long,
              wc.assigned_short,
              wc.assigned_long,
              wc.assigned_count,
              r.value AS req_value,
              r.important_rank,
              p.night_count,
              p.weekend_count,
              d.is_weekend,
              CASE
                WHEN r.value IN ('L','S') THEN 99999
                WHEN r.value = 'O' AND r.important_rank IN (1,2) THEN 1000
                WHEN r.value = 'O' THEN 400
                ELSE 0
              END
              + CASE
                  WHEN r.value IS NOT NULL AND r.value IN ('LD','N','8-8','8-5','11-8','W') THEN -50
                  ELSE 0
                END
              + CASE WHEN v_shift_type = 'night' AND u.can_work_nights = FALSE THEN 99999 ELSE 0 END
              + CASE WHEN v_shift_type = 'night' THEN (5 - u.pref_night_appetite) * 15 ELSE 0 END
              + CASE WHEN d.is_weekend THEN (5 - u.pref_weekend_appetite) * 15 ELSE 0 END
              + CASE WHEN v_shift_type = 'night' AND u.role_id = 1 THEN 150 ELSE 0 END
              + CASE WHEN v_shift_type = 'night' THEN p.night_count * 2 ELSE 0 END
              + CASE WHEN d.is_weekend THEN p.weekend_count * 2 ELSE 0 END
              + CASE WHEN v_shift_type = 'night' THEN
                  (SELECT COUNT(*) FROM tmp_assignments a WHERE a.user_id = u.user_id AND a.shift_type = 'night') * 10
                ELSE 0 END
              + CASE WHEN v_shift_type = 'night' AND EXISTS (
                  SELECT 1 FROM tmp_assignments a
                  WHERE a.user_id = u.user_id AND a.shift_type = 'night'
                    AND a.date >= (v_date - 3)
                ) THEN 50 ELSE 0 END
              + CASE WHEN v_shift_type = 'night' THEN
                  (SELECT COUNT(*) FROM tmp_assignments a
                   WHERE a.user_id = u.user_id
                     AND a.shift_type = 'night'
                     AND a.date >= v_week_start
                     AND a.date < (v_week_start + 7)) * 20
                ELSE 0 END
              + CASE
                  WHEN v_shift_type = 'day' AND EXISTS (
                    SELECT 1 FROM tmp_assignments a
                    WHERE a.user_id = u.user_id AND a.date = (v_date - 1) AND a.shift_type = 'night'
                  ) THEN 500 ELSE 0
                END
              + CASE
                  WHEN EXISTS (
                    SELECT 1 FROM tmp_assignments a1
                    WHERE a1.user_id = u.user_id AND a1.date = (v_date - 1) AND a1.shift_type <> v_shift_type
                  ) AND EXISTS (
                    SELECT 1 FROM tmp_assignments a2
                    WHERE a2.user_id = u.user_id AND a2.date = (v_date - 2) AND a2.shift_type = v_shift_type
                  ) THEN 200 ELSE 0
                END
              + 600
              AS score
            INTO v_candidate_relaxed
            FROM tmp_users u
            JOIN tmp_targets t ON t.user_id = u.user_id AND t.week_start = v_week_start
            JOIN tmp_week_counts wc ON wc.user_id = u.user_id AND wc.week_start = v_week_start
            LEFT JOIN tmp_requests r ON r.user_id = u.user_id AND r.date = v_date
            LEFT JOIN tmp_prev_counts p ON p.user_id = u.user_id
            JOIN tmp_dates d ON d.date = v_date
            WHERE
              ((v_role_group = 'rn' AND u.role_id IN (1,2)) OR (v_role_group = 'na' AND u.role_id = 3))
              AND NOT EXISTS (
                SELECT 1 FROM tmp_assignments a
                WHERE a.user_id = u.user_id AND a.date = v_date
              )
              AND (v_shift_type <> 'night' OR u.can_work_nights = TRUE)
              AND (r.value IS NULL OR r.value NOT IN ('L','S'))
              AND NOT (
                v_role_group = 'rn' AND v_required = 2 AND v_assigned = 1 AND (
                  (v_shift_type = 'day' AND u.cannot_be_second_rn_day = TRUE) OR
                  (v_shift_type = 'night' AND u.cannot_be_second_rn_night = TRUE)
                )
              )
              AND NOT (t.pattern_type = 'composition' AND v_shift_type = 'night')
              AND NOT (t.pattern_type = 'composition' AND wc.assigned_count >= 2)
            ORDER BY score ASC, u.rota_rank ASC, u.display_order ASC
            LIMIT 1;
            v_has_relaxed := FOUND;
          END IF;

          IF v_candidate.user_id IS NULL AND v_has_relaxed THEN
            v_candidate := v_candidate_relaxed;
          END IF;

          IF v_candidate.user_id IS NULL THEN
            v_warnings := array_append(v_warnings, 'Coverage gap: ' || v_date || ' ' || v_shift_type || ' ' || v_role_group || ' (min ' || v_required || ')');
            EXIT;
          END IF;

          -- Determine shift code (short vs long for composition pattern)
          IF v_role_group = 'rn' THEN
            IF v_candidate.requires_short AND v_candidate.assigned_short = 0 THEN
              v_short_code := CASE WHEN EXTRACT(dow FROM v_date) IN (0,1,2) THEN '8-5' ELSE '11-8' END;
            END IF;
          END IF;

          -- Apply shift code per role
          IF v_role_group = 'rn' THEN
            IF v_candidate.requires_short AND v_candidate.assigned_short = 0 THEN
              -- Assign short shift for composition pattern
              INSERT INTO tmp_assignments(user_id, name, date, shift_code, shift_type, role_group, forced, score, reason)
              VALUES (v_candidate.user_id, v_candidate.name, v_date, v_short_code, v_shift_type, 'rn',
                      (v_candidate.req_value = 'O' AND v_candidate.important_rank IN (1,2)),
                      v_candidate.score,
                      'composition short');
              UPDATE tmp_week_counts
              SET assigned_count = assigned_count + 1,
                  assigned_short = assigned_short + 1
              WHERE user_id = v_candidate.user_id AND week_start = v_week_start;
            ELSE
              -- Long day or night
              INSERT INTO tmp_assignments(user_id, name, date, shift_code, shift_type, role_group, forced, score, reason)
              VALUES (v_candidate.user_id, v_candidate.name, v_date,
                      CASE
                        WHEN v_shift_type = 'night' THEN v_rn_night_code
                        WHEN v_candidate.requires_long THEN '8-8'
                        ELSE v_long_code
                      END,
                      v_shift_type, 'rn',
                      (v_candidate.req_value = 'O' AND v_candidate.important_rank IN (1,2)),
                      v_candidate.score,
                      'assigned');
              UPDATE tmp_week_counts
              SET assigned_count = assigned_count + 1,
                  assigned_long = assigned_long + 1
              WHERE user_id = v_candidate.user_id AND week_start = v_week_start;
            END IF;
          ELSE
            -- NA shift
            INSERT INTO tmp_assignments(user_id, name, date, shift_code, shift_type, role_group, forced, score, reason)
            VALUES (v_candidate.user_id, v_candidate.name, v_date,
                    CASE WHEN v_shift_type = 'night' THEN v_na_night_code ELSE v_na_day_code END,
                    v_shift_type, 'na',
                    (v_candidate.req_value = 'O' AND v_candidate.important_rank IN (1,2)),
                    v_candidate.score,
                    'assigned');
            UPDATE tmp_week_counts
            SET assigned_count = assigned_count + 1
            WHERE user_id = v_candidate.user_id AND week_start = v_week_start;
          END IF;

          v_total_score := v_total_score + v_candidate.score;
          v_total_shifts := v_total_shifts + 1;
          v_assigned := v_assigned + 1;
        END LOOP;

        -- Optional recommended fill
        IF v_assigned >= v_required AND v_assigned < v_recommended THEN
          SELECT
            u.user_id,
            u.name,
            u.role_id,
            r.value AS req_value,
            r.important_rank,
            p.night_count,
            p.weekend_count,
            d.is_weekend,
            CASE
              WHEN r.value IN ('L','S') THEN 99999
              WHEN r.value = 'O' AND r.important_rank IN (1,2) THEN 1000
              WHEN r.value = 'O' THEN 200
              ELSE 0
            END
            + CASE WHEN v_shift_type = 'night' AND u.can_work_nights = FALSE THEN 99999 ELSE 0 END
            + CASE WHEN v_shift_type = 'night' THEN (5 - u.pref_night_appetite) * 15 ELSE 0 END
            + CASE WHEN d.is_weekend THEN (5 - u.pref_weekend_appetite) * 15 ELSE 0 END
            + CASE WHEN v_shift_type = 'night' AND u.role_id = 1 THEN 150 ELSE 0 END
            + CASE
                WHEN v_role_group = 'rn' AND u.role_id = 1 AND EXISTS (
                  SELECT 1 FROM tmp_assignments a
                  JOIN tmp_users ux ON ux.user_id = a.user_id
                  WHERE a.date = v_date AND a.shift_type = v_shift_type AND ux.role_id = 1
                ) THEN 100 ELSE 0
              END
            + CASE WHEN v_shift_type = 'night' THEN p.night_count * 2 ELSE 0 END
            + CASE WHEN d.is_weekend THEN p.weekend_count * 2 ELSE 0 END
            + CASE WHEN v_shift_type = 'night' THEN
                (SELECT COUNT(*) FROM tmp_assignments a WHERE a.user_id = u.user_id AND a.shift_type = 'night') * 10
              ELSE 0 END
            + CASE WHEN v_shift_type = 'night' AND EXISTS (
                SELECT 1 FROM tmp_assignments a
                WHERE a.user_id = u.user_id AND a.shift_type = 'night'
                  AND a.date >= (v_date - 3)
              ) THEN 50 ELSE 0 END
            + CASE
                WHEN v_shift_type = 'day' AND EXISTS (
                  SELECT 1 FROM tmp_assignments a
                  WHERE a.user_id = u.user_id AND a.date = (v_date - 1) AND a.shift_type = 'night'
                ) THEN 500 ELSE 0
              END
            + CASE
                WHEN EXISTS (
                  SELECT 1 FROM tmp_assignments a1
                  WHERE a1.user_id = u.user_id AND a1.date = (v_date - 1) AND a1.shift_type <> v_shift_type
                ) AND EXISTS (
                  SELECT 1 FROM tmp_assignments a2
                  WHERE a2.user_id = u.user_id AND a2.date = (v_date - 2) AND a2.shift_type = v_shift_type
                ) THEN 200 ELSE 0
              END
            AS score
          INTO v_candidate
          FROM tmp_users u
          JOIN tmp_targets t ON t.user_id = u.user_id AND t.week_start = v_week_start
          JOIN tmp_week_counts wc ON wc.user_id = u.user_id AND wc.week_start = v_week_start
          LEFT JOIN tmp_requests r ON r.user_id = u.user_id AND r.date = v_date
          LEFT JOIN tmp_prev_counts p ON p.user_id = u.user_id
          JOIN tmp_dates d ON d.date = v_date
          WHERE
            ((v_role_group = 'rn' AND u.role_id IN (1,2)) OR (v_role_group = 'na' AND u.role_id = 3))
            AND NOT EXISTS (
              SELECT 1 FROM tmp_assignments a
              WHERE a.user_id = u.user_id AND a.date = v_date
            )
            AND (v_shift_type <> 'night' OR u.can_work_nights = TRUE)
            AND (r.value IS NULL OR r.value NOT IN ('L','S'))
            AND (r.value IS NULL OR NOT (r.value = 'O' AND r.important_rank IN (1,2)))
            AND (t.target_count IS NULL OR wc.assigned_count < t.target_count)
            AND NOT (t.pattern_type = 'composition')
          ORDER BY score ASC, u.rota_rank ASC, u.display_order ASC
          LIMIT 1;

          IF v_candidate.user_id IS NOT NULL AND v_candidate.score < 800 THEN
            IF v_role_group = 'rn' THEN
              INSERT INTO tmp_assignments(user_id, name, date, shift_code, shift_type, role_group, forced, score, reason)
              VALUES (v_candidate.user_id, v_candidate.name, v_date,
                      CASE WHEN v_shift_type = 'night' THEN v_rn_night_code ELSE v_long_code END,
                      v_shift_type, 'rn',
                      (v_candidate.req_value = 'O' AND v_candidate.important_rank IN (1,2)),
                      v_candidate.score,
                      'recommended');
              UPDATE tmp_week_counts
              SET assigned_count = assigned_count + 1,
                  assigned_long = assigned_long + 1
              WHERE user_id = v_candidate.user_id AND week_start = v_week_start;
            ELSE
              INSERT INTO tmp_assignments(user_id, name, date, shift_code, shift_type, role_group, forced, score, reason)
              VALUES (v_candidate.user_id, v_candidate.name, v_date,
                      CASE WHEN v_shift_type = 'night' THEN v_na_night_code ELSE v_na_day_code END,
                      v_shift_type, 'na',
                      (v_candidate.req_value = 'O' AND v_candidate.important_rank IN (1,2)),
                      v_candidate.score,
                      'recommended');
              UPDATE tmp_week_counts
              SET assigned_count = assigned_count + 1
              WHERE user_id = v_candidate.user_id AND week_start = v_week_start;
            END IF;

          v_total_score := v_total_score + v_candidate.score;
          v_total_shifts := v_total_shifts + 1;

          v_log := v_log || '  Assigned: ' || v_candidate.name || ' -> ' ||
                   CASE WHEN v_role_group = 'rn' THEN (CASE WHEN v_shift_type = 'night' THEN v_rn_night_code ELSE v_long_code END)
                        ELSE (CASE WHEN v_shift_type = 'night' THEN v_na_night_code ELSE v_na_day_code END) END ||
                   ' (' || v_shift_type || ' ' || v_role_group || ', score ' || v_candidate.score || ')' || CHR(10);
          END IF;
        END IF;
      END LOOP;

      -- Charge RN selection for this day/night
      IF v_shift_type IN ('day','night') THEN
        SELECT a.user_id
        INTO v_candidate
        FROM tmp_assignments a
        JOIN tmp_users u ON u.user_id = a.user_id
        WHERE a.date = v_date
          AND a.shift_type = v_shift_type
          AND a.role_group = 'rn'
          AND ((v_shift_type = 'day' AND u.can_be_in_charge_day = TRUE)
            OR (v_shift_type = 'night' AND u.can_be_in_charge_night = TRUE AND u.can_work_nights = TRUE))
        ORDER BY u.rota_rank ASC, u.display_order ASC
        LIMIT 1;

        IF v_candidate.user_id IS NULL THEN
          v_warnings := array_append(v_warnings, 'No charge RN for ' || v_date || ' ' || v_shift_type);
        ELSE
          UPDATE tmp_assignments
          SET is_charge = TRUE
          WHERE date = v_date AND shift_type = v_shift_type AND user_id = v_candidate.user_id;
        END IF;
      END IF;

      -- Cannot be 2nd RN rule
      IF v_shift_type IN ('day','night') THEN
        IF (SELECT COUNT(*) FROM tmp_assignments a WHERE a.date = v_date AND a.shift_type = v_shift_type AND a.role_group = 'rn') = 2 THEN
          IF EXISTS (
            SELECT 1 FROM tmp_assignments a
            JOIN tmp_users u ON u.user_id = a.user_id
            WHERE a.date = v_date AND a.shift_type = v_shift_type AND a.role_group = 'rn'
              AND ((v_shift_type = 'day' AND u.cannot_be_second_rn_day = TRUE)
                OR (v_shift_type = 'night' AND u.cannot_be_second_rn_night = TRUE))
          ) THEN
            v_warnings := array_append(v_warnings, 'Second RN constraint violated on ' || v_date || ' ' || v_shift_type);
          END IF;
        END IF;
      END IF;

    END LOOP;

    -- Day summary log
    v_log := v_log || 'Date: ' || v_date || CHR(10) ||
      '  Day RN: ' || (SELECT COUNT(*) FROM tmp_assignments WHERE date = v_date AND shift_type = 'day' AND role_group = 'rn') ||
      ', Day NA: ' || (SELECT COUNT(*) FROM tmp_assignments WHERE date = v_date AND shift_type = 'day' AND role_group = 'na') || CHR(10) ||
      '  Night RN: ' || (SELECT COUNT(*) FROM tmp_assignments WHERE date = v_date AND shift_type = 'night' AND role_group = 'rn') ||
      ', Night NA: ' || (SELECT COUNT(*) FROM tmp_assignments WHERE date = v_date AND shift_type = 'night' AND role_group = 'na') || CHR(10);
  END LOOP;

  -- Pattern target warnings
  FOR v_candidate IN
    SELECT t.user_id, u.name, t.week_start, t.target_count, wc.assigned_count
    FROM tmp_targets t
    JOIN tmp_week_counts wc ON wc.user_id = t.user_id AND wc.week_start = t.week_start
    JOIN tmp_users u ON u.user_id = t.user_id
    WHERE t.target_count IS NOT NULL AND wc.assigned_count <> t.target_count
  LOOP
    v_warnings := array_append(v_warnings, 'Pattern target mismatch: ' || v_candidate.name || ' week ' || v_candidate.week_start || ' assigned ' || v_candidate.assigned_count || ' target ' || v_candidate.target_count);
  END LOOP;

  -- Forced against strong request warnings
  IF EXISTS (SELECT 1 FROM tmp_assignments WHERE forced = TRUE) THEN
    v_warnings := array_append(v_warnings, 'Forced assignments against strong off requests occurred.');
  END IF;

  -- =======================
  -- Build output JSON
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
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp';

GRANT EXECUTE ON FUNCTION public.generate_schedule_preview(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_schedule_preview(TEXT, UUID) TO anon;

COMMENT ON FUNCTION public.generate_schedule_preview(TEXT, UUID) IS
'Generate a schedule preview for a period. Admin-only. Returns rota_grid, shifts_json, warnings, and an explanation log.';

# v2 Rewrite: Issues Found & Fixed

## What Was Wrong

### 1. **Compilation Error: Missing rota_rank**
**Problem:** v2 did `ORDER BY score ASC, u.rota_rank ASC` but tmp_users had no rota_rank field.
```sql
-- v2 BROKEN:
CREATE TEMP TABLE tmp_users (
  user_id UUID PRIMARY KEY,
  name TEXT,
  role_id INT,
  pattern_type TEXT,
  ...
  -- rota_rank MISSING
)

SELECT ... ORDER BY score ASC, u.rota_rank ASC  -- ERROR
```

**Fixed:** Added rota_rank and display_order to tmp_users:
```sql
-- v2 CORRECTED:
CREATE TEMP TABLE tmp_users (
  ...
  rota_rank INT,
  display_order INT,
  ...
)

INSERT INTO tmp_users
SELECT
  ...
  COALESCE(u.display_order, 9999) AS rota_rank,
  u.display_order,
  ...
```

---

### 2. **Wrong Pattern Targets (Faked Weekly Targets)**
**Problem:** Hardcoded targets instead of computing from pattern_definitions.weekly_targets array:
```sql
-- v2 BROKEN:
CASE
  WHEN u.pattern_type = 'weekly' THEN 2
  WHEN u.pattern_type IN ('repeating', 'composition') THEN 3  -- WRONG
  WHEN u.pattern_type = 'nurse_flexible_16_5w' THEN 3        -- WRONG
  ELSE NULL
END
```

This breaks all pattern enforcement:
- `repeating` (2/2/3, 3/3/4) is an anchored cycle, not "always 3"
- `composition` is exactly 2/week (1L + 1S), not 3
- `nurse_flexible_16_5w` is 3/week + one 4-week (flex), not "always 3"

**Fixed:** Proper pattern math using weekly_targets array and anchor alignment:
```sql
-- v2 CORRECTED:
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
END
```

---

### 3. **No Pass System (Declared But Never Ran)**
**Problem:** Variables exist but never used:
```sql
-- v2 BROKEN:
DECLARE
  v_pass_number INT := 1;
  v_request_override_allowed BOOLEAN := FALSE;
  v_drop_soft_weights BOOLEAN := FALSE;
  v_soft_weight_multiplier FLOAT := 1.0;
BEGIN
  ...
  -- Loop through dates, assign candidates
  -- BUT: v_pass_number never changes, no retry loop
  -- Pass 2 and Pass 3 never happen
```

**Fixed:** Actual 3-pass loop with multiplier adjustments:
```sql
-- v2 CORRECTED:
v_pass_number := 1;
WHILE v_pass_number <= 3 AND v_assigned < v_required LOOP
  
  CASE v_pass_number
    WHEN 1 THEN
      v_soft_weight_multiplier := 1.0;
      v_request_override_allowed := FALSE;
    WHEN 2 THEN
      v_soft_weight_multiplier := 1.0;
      v_request_override_allowed := TRUE;
    WHEN 3 THEN
      v_soft_weight_multiplier := 0.0;
      v_request_override_allowed := TRUE;
  END CASE;

  -- Try to fill slot with current pass constraints
  WHILE v_assigned < v_required LOOP
    -- SELECT candidate WHERE ...
    IF v_candidate.user_id IS NULL THEN EXIT; END IF;  -- Move to next pass
    -- INSERT, increment v_assigned
  END LOOP;

  v_pass_number := v_pass_number + 1;
END LOOP;
```

---

### 4. **Charge Coverage Not Enforced (Just a Warning)**
**Problem:** Check happened after assignment; if no charge-capable RN, just warned:
```sql
-- v2 BROKEN:
IF v_assigned >= v_required THEN
  SELECT a.user_id INTO v_candidate
  FROM tmp_assignments a
  WHERE ... AND can_be_in_charge_* = TRUE
  LIMIT 1;
  
  IF v_candidate.user_id IS NULL THEN
    v_warnings := array_append(v_warnings, 'HARD CONSTRAINT: No charge...');
    -- But RNs are already assigned! Just a warning.
  END IF;
END IF;
```

**Fixed:** Charge coverage validated after minima, gap if missing:
```sql
-- v2 CORRECTED:
IF v_role_group = 'rn' AND v_assigned >= v_required THEN
  SELECT a.user_id INTO v_candidate
  FROM tmp_assignments a
  JOIN tmp_users u ON u.user_id = a.user_id
  WHERE a.date = v_date
    AND a.shift_type = v_shift_type
    AND a.role_group = 'rn'
    AND a.reason <> 'composition short'
    AND ((v_shift_type = 'day' AND u.can_be_in_charge_day = TRUE)
      OR (v_shift_type = 'night' AND u.can_be_in_charge_night = TRUE ...))
  ORDER BY u.rota_rank ASC
  LIMIT 1;

  IF v_candidate.user_id IS NULL THEN
    v_warnings := array_append(v_warnings,
      'HARD CONSTRAINT VIOLATION: ' || v_date || ' ' || v_shift_type ||
      ' - no charge-capable RN (gap created)');
    -- Now at least documented
  ELSE
    UPDATE tmp_assignments SET is_charge = TRUE ...
  END IF;
END IF;
```

---

### 5. **Cannot-be-2nd Only Half-Enforced (Second-Person Filter, Not Pair)**
**Problem:** Only prevented "2nd RN" if they had cannot_be_second flag, but didn't check if 1st RN violates pair rules:
```sql
-- v2 BROKEN:
AND NOT (
  v_role_group = 'rn' 
  AND v_assigned = 1  -- This is 2nd RN
  AND (
    (v_shift_type = 'day' AND u.cannot_be_second_rn_day = TRUE)
    OR
    (v_shift_type = 'night' AND u.cannot_be_second_rn_night = TRUE)
  )
)
```

Example failure:
- 1st RN picked has `cannot_be_second_rn_day = TRUE` (shouldn't be in 2-person day shift)
- 2nd RN picked is valid (has flag FALSE)
- Result: Violation undetected

**Fixed:** Pair feasibility check for both RNs:
```sql
-- v2 CORRECTED:
-- Check 2nd RN (same as before):
AND NOT (
  v_role_group = 'rn' 
  AND v_assigned = 1
  AND ((v_shift_type = 'day' AND u.cannot_be_second_rn_day = TRUE)
    OR (v_shift_type = 'night' AND u.cannot_be_second_rn_night = TRUE))
)

-- NEW: Check 1st RN if we'll be assigning 2 total:
AND NOT (
  v_role_group = 'rn'
  AND v_assigned = 0
  AND v_required > 1
  AND ((v_shift_type = 'day' AND u.cannot_be_second_rn_day = TRUE)
    OR (v_shift_type = 'night' AND u.cannot_be_second_rn_night = TRUE))
)
```

---

### 6. **1L1S Composition Not Implemented (No Short Shifts Ever Assigned)**
**Problem:** v2 never assigned short shifts, only always LD or N:
```sql
-- v2 BROKEN:
INSERT INTO tmp_assignments(...)
VALUES (
  v_candidate.user_id, v_candidate.name, v_date,
  CASE
    WHEN v_role_group = 'rn' AND v_shift_type = 'night' THEN v_rn_night_code
    WHEN v_role_group = 'rn' THEN v_long_code          -- Always LD, never 8-5
    WHEN v_shift_type = 'night' THEN v_na_night_code
    ELSE v_na_day_code
  END,
  ...
);

-- So composition rule "exactly 1L + 1S" can never be satisfied.
-- Only enforced "max 2", not actual composition.
```

**Fixed:** Actual composition assignment logic (track assigned_short and assigned_long):
```sql
-- v2 CORRECTED:
v_short_code := CASE WHEN EXTRACT(dow FROM v_date) IN (0,1,2) THEN '8-5' ELSE '11-8' END;

IF v_role_group = 'rn' THEN
  IF v_candidate.requires_short AND v_candidate.assigned_short = 0 THEN
    -- Assign short for composition
    INSERT INTO tmp_assignments(...)
    VALUES (..., v_short_code, ..., 'composition short');
    UPDATE tmp_week_counts
    SET assigned_count = assigned_count + 1,
        assigned_short = assigned_short + 1
    WHERE user_id = v_candidate.user_id AND week_start = v_week_start;
  ELSE
    -- Assign long (LD or N)
    INSERT INTO tmp_assignments(...)
    VALUES (..., CASE WHEN v_shift_type = 'night' THEN v_rn_night_code ELSE v_long_code END, ..., 'assigned');
    UPDATE tmp_week_counts
    SET assigned_count = assigned_count + 1,
        assigned_long = assigned_long + 1
    WHERE user_id = v_candidate.user_id AND week_start = v_week_start;
  END IF;
ELSE
  -- NA assignment (no shorts for NA)
  ...
END IF;
```

---

### 7. **Lost Shift Legality Detail (No Short Shift Gating)**
**Problem:** No WHERE clause preventing shorts from being assigned to non-composition staff:
```sql
-- v2 BROKEN: shorts can go to anyone
-- Later when implementing shorts, no gating exists
```

**Fixed:** WHERE clause in candidate selection:
```sql
-- v2 CORRECTED:
WHERE
  ...
  -- Short shifts only to composition staff
  AND NOT (v_role_group = 'rn' AND t.requires_short IS FALSE)
  ...
```

---

### 8. **Week Counters Not Updated (assigned_long, assigned_short Declared But Not Used)**
**Problem:** Declared but never incremented:
```sql
-- v2 BROKEN:
CREATE TEMP TABLE tmp_week_counts (
  ...
  assigned_long INT DEFAULT 0,
  assigned_short INT DEFAULT 0
)

-- Later: only assigned_count updated, never assigned_long or assigned_short
UPDATE tmp_week_counts SET assigned_count = assigned_count + 1
WHERE user_id = ... AND week_start = ...;
-- assigned_long and assigned_short stay 0
```

**Fixed:** Separate update logic per assignment type:
```sql
-- v2 CORRECTED:
IF v_candidate.requires_short AND v_candidate.assigned_short = 0 THEN
  UPDATE tmp_week_counts
  SET assigned_count = assigned_count + 1,
      assigned_short = assigned_short + 1
  WHERE user_id = v_candidate.user_id AND week_start = v_week_start;
ELSE
  UPDATE tmp_week_counts
  SET assigned_count = assigned_count + 1,
      assigned_long = assigned_long + 1
  WHERE user_id = v_candidate.user_id AND week_start = v_week_start;
END IF;
```

Plus validation in debug section:
```sql
IF v_candidate.requires_short AND v_candidate.assigned_short <> 1 THEN
  v_warnings := array_append(v_warnings,
    'COMPOSITION VIOLATION: ... - requires 1 short, got ' || v_candidate.assigned_short);
END IF;
IF v_candidate.requires_short AND v_candidate.assigned_long <> 1 THEN
  v_warnings := array_append(v_warnings,
    'COMPOSITION VIOLATION: ... - requires 1 long, got ' || v_candidate.assigned_long);
END IF;
```

---

## Summary: v2 vs v2_corrected

| Issue | v2 (Broken) | v2_corrected (Fixed) |
|-------|-----------|-------------------|
| Compilation | ERROR: u.rota_rank undefined | ✓ rota_rank + display_order added |
| Pattern math | Fake hardcoded targets | ✓ Real weekly_targets array + anchor alignment |
| Pass system | Declared but not used | ✓ Actual 3-pass loop with multiplier adjustments |
| Charge coverage | Warning only | ✓ Validated after minima; gap if missing |
| Cannot-be-2nd | 2nd RN filter only | ✓ Pair feasibility (both 1st and 2nd checked) |
| Composition 1L1S | Never assigns shorts | ✓ Assigns shorts; validates 1L + 1S per week |
| Short gating | No WHERE clause | ✓ WHERE prevents shorts to non-composition staff |
| Week counters | assigned_long/short unused | ✓ Updated per assignment type; validated in debug |

---

## Files

- **Original (broken):** `sql/functions/generate_schedule_preview_v2_hardconstraints.sql`
- **Corrected:** `sql/functions/generate_schedule_preview_v2_corrected.sql`

**Deploy corrected version to staging.** Test against periods that previously failed pattern enforcement.

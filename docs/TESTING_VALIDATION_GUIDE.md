# Testing & Validation Guide for Hard Constraint Enforcement

## Overview
This guide walks through validating that the new `generate_schedule_preview_v2` function properly enforces hard constraints and leaves gaps instead of silently violating rules.

---

## Test Suite

### Test 1: Pattern Quota Enforcement
**Scenario:** A user with pattern "2/week" (exactly 2 shifts per week) is assigned to a period.

**Expected Output:**
- For each week, user should have exactly 2 shifts (or warning if pattern exception)
- If week fills (2 shifts assigned), candidate is rejected for 3rd assignment
- Warning log includes: "PATTERN MISMATCH: [Name] week [N] - target 2, assigned X" (if X ≠ 2)

**Validation SQL:**
```sql
SELECT
  name,
  week_num,
  target_count,
  assigned_count,
  (assigned_count = target_count) AS pattern_matched,
  CASE
    WHEN assigned_count = target_count THEN '✓ OK'
    ELSE '✗ PATTERN VIOLATION'
  END AS status
FROM (
  SELECT
    u.name,
    w.week_index AS week_num,
    t.target_count,
    COUNT(a.user_id) AS assigned_count
  FROM tmp_users u
  CROSS JOIN tmp_weeks w
  LEFT JOIN tmp_targets t ON t.user_id = u.user_id AND t.week_start = w.week_start
  LEFT JOIN tmp_assignments a ON a.user_id = u.user_id 
    AND a.date >= w.week_start AND a.date < (w.week_start + 7)
  WHERE u.pattern_type = 'weekly'
  GROUP BY u.user_id, u.name, w.week_index, t.target_count
) AS results
ORDER BY name, week_num;
```

---

### Test 2: Cannot-be-2nd RN Enforcement
**Scenario:** A user with `cannot_be_second_rn_day = true` is in the pool. On a day shift, 2 RNs are needed.

**Expected Output:**
- If this user is selected, they must be 1st RN (not 2nd)
- 2nd RN must have `cannot_be_second_rn_day = false` (or not selected at all if none available)
- If violation occurs, warning: "HARD CONSTRAINT: [Name] cannot be 2nd RN on [date]"

**Validation SQL:**
```sql
SELECT
  a.date,
  a.shift_type,
  STRING_AGG(u.name || ' (second=' || u.cannot_be_second_rn_day || ')', ', ') AS assigned_rns,
  CASE
    WHEN COUNT(*) = 2 AND MAX(CASE WHEN u.cannot_be_second_rn_day THEN 1 ELSE 0 END) > 0
      THEN '✗ CANNOT-BE-2ND VIOLATION'
    ELSE '✓ OK'
  END AS status
FROM tmp_assignments a
JOIN tmp_users u ON u.user_id = a.user_id
WHERE a.shift_type = 'day' AND a.role_group = 'rn'
GROUP BY a.date, a.shift_type
HAVING COUNT(*) = 2
ORDER BY a.date;
```

---

### Test 3: Charge Coverage (Hard)
**Scenario:** A shift is assigned. It must have at least one RN with `can_be_in_charge_day=true` (or night equivalent).

**Expected Output:**
- For every shift with RNs assigned, at least one must have charge capability
- If none available, warning: "HARD CONSTRAINT: No charge-capable RN for [date] [shift]"
- Gap left (no RN assigned) if filling it would require non-capable RN

**Validation SQL:**
```sql
SELECT
  a.date,
  a.shift_type,
  STRING_AGG(u.name, ', ') AS assigned_rns,
  MAX(CASE WHEN a.shift_type = 'day' AND u.can_be_in_charge_day THEN 1
           WHEN a.shift_type = 'night' AND u.can_be_in_charge_night THEN 1
           ELSE 0 END) AS has_charge,
  CASE
    WHEN MAX(CASE WHEN a.shift_type = 'day' AND u.can_be_in_charge_day THEN 1
                  WHEN a.shift_type = 'night' AND u.can_be_in_charge_night THEN 1
                  ELSE 0 END) = 1 THEN '✓ OK'
    ELSE '✗ NO CHARGE COVERAGE'
  END AS status
FROM tmp_assignments a
JOIN tmp_users u ON u.user_id = a.user_id
WHERE a.role_group = 'rn'
GROUP BY a.date, a.shift_type
ORDER BY a.date, a.shift_type;
```

---

### Test 4: Nights Capability Enforcement
**Scenario:** A user with `can_work_nights = false` is in the pool.

**Expected Output:**
- This user is never assigned to N (night shift)
- If all N assignments were blocked, gap left and warning issued
- No silent violations

**Validation SQL:**
```sql
SELECT
  u.name,
  u.can_work_nights,
  COUNT(CASE WHEN a.shift_type = 'night' THEN 1 END) AS night_shifts_assigned,
  CASE
    WHEN u.can_work_nights = FALSE AND COUNT(CASE WHEN a.shift_type = 'night' THEN 1 END) > 0
      THEN '✗ NIGHTS CAPABILITY VIOLATION'
    ELSE '✓ OK'
  END AS status
FROM tmp_users u
LEFT JOIN tmp_assignments a ON a.user_id = u.user_id
GROUP BY u.user_id, u.name, u.can_work_nights
ORDER BY u.name;
```

---

### Test 5: Shift Legality
**Scenario:** RNs should only get LD or N; NAs should only get 8-8 or N.

**Expected Output:**
- No illegal combinations (e.g., RN with 8-8, NA with LD)
- If detected, warning: "SHIFT LEGALITY VIOLATION: [Name] ([role]) assigned [code]"

**Validation SQL:**
```sql
SELECT
  a.date,
  a.shift_code,
  u.name,
  u.role_id,
  CASE WHEN u.role_id IN (1,2) THEN 'RN' ELSE 'NA' END AS role_label,
  CASE
    WHEN u.role_id IN (1,2) AND a.shift_code NOT IN ('LD', 'N', '11-8')
      THEN '✗ ILLEGAL: RN with ' || a.shift_code
    WHEN u.role_id = 3 AND a.shift_code NOT IN ('8-8', 'N')
      THEN '✗ ILLEGAL: NA with ' || a.shift_code
    ELSE '✓ OK'
  END AS status
FROM tmp_assignments a
JOIN tmp_users u ON u.user_id = a.user_id
ORDER BY a.date, u.role_id;
```

---

### Test 6: Ward Minima Coverage
**Scenario:** Every day must have RN day ≥2, RN night ≥2, NA day ≥3, NA night ≥1 (or documented gap).

**Expected Output:**
- For each date/shift/role, count ≥ required (or gap explicitly left)
- Warnings for unmet minima: "HARD CONSTRAINT GAP: [date] [shift] [role] - required N, got M"

**Validation SQL:**
```sql
SELECT
  d.date,
  'day' AS shift_type,
  'rn' AS role_group,
  2 AS required,
  COUNT(CASE WHEN a.shift_type = 'day' AND a.role_group = 'rn' THEN 1 END) AS assigned,
  CASE
    WHEN COUNT(CASE WHEN a.shift_type = 'day' AND a.role_group = 'rn' THEN 1 END) >= 2
      THEN '✓ OK'
    ELSE '✗ COVERAGE GAP'
  END AS status
FROM tmp_dates d
LEFT JOIN tmp_assignments a ON a.date = d.date
GROUP BY d.date
HAVING COUNT(CASE WHEN a.shift_type = 'day' AND a.role_group = 'rn' THEN 1 END) < 2
ORDER BY d.date;
```

---

## Manual Testing Steps

### Step 1: Run v2 on a Test Period
```sql
SELECT
  rota_grid,
  shifts_json,
  explanation_log,
  period_score,
  total_shifts,
  warnings
FROM public.generate_schedule_preview_v2(
  p_token => '<admin_session_token>',
  p_period_id => '<test_period_uuid>'
);
```

### Step 2: Inspect Warnings
Copy the `warnings` array from the result:
```
PATTERN MISMATCH: Paul week 0 - target 2, assigned 1
HARD CONSTRAINT GAP: 2026-01-21 night rn - required 2, got 1
```

### Step 3: Validate Against Criteria
For each warning:
- Is it expected given the staff pool and constraints?
- Does it explain WHY the slot is empty?
- If unexpected, is it a data bug or a genuine constraint violation?

### Step 4: Compare to Old Version
```sql
SELECT
  rota_grid,
  shifts_json,
  explanation_log,
  period_score,
  total_shifts,
  warnings
FROM public.generate_schedule_preview(
  p_token => '<admin_session_token>',
  p_period_id => '<test_period_uuid>'
);
```

- **Old version:** Rules violated silently in rota_grid (no warning)
- **v2 version:** Gaps left, warnings explain WHY

### Step 5: Verify Output Consistency
- Rota grid should have fewer total shifts (because gaps replace violations)
- Period score may be lower (harder constraints respected)
- Warnings should clearly indicate which rules prevented filling slots

---

## Known Issues & Debugging

### Issue: Pattern quota not enforced
**Check:**
- Is `target_count` being computed correctly?
- Does the user have a `user_pattern` record?
- Are week boundaries correct?

**Debug:**
```sql
SELECT
  u.name,
  u.pattern_type,
  t.week_start,
  t.target_count,
  wc.assigned_count
FROM tmp_users u
LEFT JOIN tmp_targets t ON t.user_id = u.user_id
LEFT JOIN tmp_week_counts wc ON wc.user_id = u.user_id AND wc.week_start = t.week_start
WHERE u.name = '<test_user>'
ORDER BY t.week_start;
```

### Issue: Gap left unexpectedly
**Check:**
- Are there hard constraint violations in the warnings?
- Is a user's `can_work_nights`, `cannot_be_second_rn_*`, or role mismatch causing rejection?

**Debug:**
Look at warnings for "HARD CONSTRAINT GAP" with reason.

### Issue: Cannot-be-2nd not enforced
**Check:**
- Is `cannot_be_second_rn_day` or `cannot_be_second_rn_night` correctly set in users table?

**Debug:**
```sql
SELECT
  name,
  cannot_be_second_rn_day,
  cannot_be_second_rn_night
FROM tmp_users
WHERE name IN ('<user1>', '<user2>');
```

---

## Acceptance Criteria for v2

A schedule generated by v2 passes validation if:

- [ ] No shift has an illegal shift_code for its assigned user's role
- [ ] No user exceeds their pattern's weekly target (or exception is documented in warnings)
- [ ] All "cannot-be-2nd" users are never 2nd RN on any shift
- [ ] Every assigned shift has charge coverage (or gap flagged)
- [ ] Ward minima met or documented gaps with reason
- [ ] All hard constraint violations result in explicit gaps + warnings (no silent violations)

If any criterion fails → v2 is not ready; debug and retest.

---

## Sign-Off

Once all tests pass:

- [ ] v2 function deployed to production
- [ ] Admin UI switched to use v2 by default
- [ ] Old function retained for backup (deprecated)
- [ ] Documentation updated with new constraint model

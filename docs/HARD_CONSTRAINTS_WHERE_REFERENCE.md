# Hard Constraints Reference: WHERE Clauses

Quick lookup for how each hard constraint is enforced in the WHERE clause of candidate selection.

---

## 1. Role Eligibility

```sql
WHERE
  ((v_role_group = 'rn' AND u.role_id IN (1,2)) 
   OR 
   (v_role_group = 'na' AND u.role_id = 3))
```

**Effect:** Only RNs (role_id 1,2) can be selected for RN shifts; only NAs (role_id 3) for NA shifts.

---

## 2. No Double Assignment (Same Day)

```sql
WHERE
  NOT EXISTS (
    SELECT 1 FROM tmp_assignments a
    WHERE a.user_id = u.user_id AND a.date = v_date
  )
```

**Effect:** Once a user is assigned to any shift on a date, they're excluded from further assignments that day.

---

## 3. Shift Legality (Implicit)

Enforced via the CASE statement that assigns shift codes:

```sql
CASE
  WHEN v_role_group = 'rn' AND v_shift_type = 'night' THEN 'N'
  WHEN v_role_group = 'rn' THEN 'LD'
  WHEN v_shift_type = 'night' THEN 'N'
  WHEN v_role_group = 'na' THEN '8-8'
END
```

**Effect:** Impossible to assign RN to 8-8, NA to LD, etc. Shift codes are deterministic per role.

---

## 4. Nights Capability

```sql
WHERE
  (v_shift_type <> 'night' OR u.can_work_nights = TRUE)
```

**Logic:** If it's a night shift AND can_work_nights is false, exclude.  
**Effect:** Non-capable staff never selected for N shifts.

---

## 5. Hard Leave/Sick Exclusion

```sql
WHERE
  (r.value IS NULL OR r.value NOT IN ('L','S'))
```

**Logic:** If request exists and value is L (leave) or S (sick), exclude.  
**Effect:** Never override hard leave/sick requests; they're non-negotiable.

---

## 6. Pattern Quota Not Exceeded

```sql
WHERE
  (t.target_count IS NULL OR wc.assigned_count < t.target_count)
```

**Logic:** If user has a pattern target, allow only if current week count < target.  
**Effect:** Once a user hits their weekly quota, they're rejected for further assignments that week.

---

## 7. Composition Pattern (1L1S) Max 2

```sql
WHERE
  NOT (t.pattern_type = 'composition' AND wc.assigned_count >= 2)
```

**Logic:** If pattern is 'composition', reject if already have 2 assignments this week.  
**Effect:** Composition staff get at most 2 assignments per week (forcing 1L + 1S structure).

---

## 8. Cannot-be-2nd RN Check

```sql
WHERE
  NOT (
    v_role_group = 'rn'
    AND v_assigned = 1  -- This is the 2nd RN being selected
    AND (
      (v_shift_type = 'day' AND u.cannot_be_second_rn_day = TRUE)
      OR
      (v_shift_type = 'night' AND u.cannot_be_second_rn_night = TRUE)
    )
  )
```

**Logic:** 
- `v_assigned = 1` means we're selecting the 2nd RN (1st is already assigned)
- If user has `cannot_be_second_rn_day=true` and it's a day shift, reject
- If user has `cannot_be_second_rn_night=true` and it's a night shift, reject

**Effect:** Users flagged "can't be 2nd" are always 1st or not assigned at all.

---

## Combined WHERE Example

```sql
WHERE
  -- Role eligibility
  ((v_role_group = 'rn' AND u.role_id IN (1,2)) 
   OR 
   (v_role_group = 'na' AND u.role_id = 3))
  
  -- No double assignment
  AND NOT EXISTS (
    SELECT 1 FROM tmp_assignments a
    WHERE a.user_id = u.user_id AND a.date = v_date
  )
  
  -- Nights capability
  AND (v_shift_type <> 'night' OR u.can_work_nights = TRUE)
  
  -- Hard leave/sick
  AND (r.value IS NULL OR r.value NOT IN ('L','S'))
  
  -- Pattern quota
  AND (t.target_count IS NULL OR wc.assigned_count < t.target_count)
  
  -- Composition max 2
  AND NOT (t.pattern_type = 'composition' AND wc.assigned_count >= 2)
  
  -- Cannot-be-2nd
  AND NOT (
    v_role_group = 'rn' 
    AND v_assigned = 1
    AND (
      (v_shift_type = 'day' AND u.cannot_be_second_rn_day = TRUE)
      OR
      (v_shift_type = 'night' AND u.cannot_be_second_rn_night = TRUE)
    )
  )
```

---

## Soft Constraints (NOT in WHERE, only in SCORE)

These are computed in the SELECT but don't filter candidates:

```sql
-- Fairness: nights
CASE WHEN v_shift_type = 'night' THEN p.night_count * 2 * v_soft_weight_multiplier ELSE 0 END

-- Fairness: weekends
CASE WHEN d.is_weekend THEN p.weekend_count * 2 * v_soft_weight_multiplier ELSE 0 END

-- Preferences: night appetite
CASE WHEN v_shift_type = 'night' THEN (5 - u.pref_night_appetite) * 15 * v_soft_weight_multiplier ELSE 0 END

-- Preferences: weekend appetite
CASE WHEN d.is_weekend THEN (5 - u.pref_weekend_appetite) * 15 * v_soft_weight_multiplier ELSE 0 END

-- Request override (soft in Pass 2+)
CASE
  WHEN r.value = 'O' AND r.important_rank IN (1,2) AND NOT v_request_override_allowed THEN 1000
  WHEN r.value = 'O' THEN 200
  ELSE 0
END
```

**Effect:** Higher scores = less preferred. Candidates sorted by ascending score. Best candidate wins, as long as they pass all WHERE constraints.

---

## Charge Coverage Check (Post-Assignment)

```sql
-- After assigning N RNs, verify at least one has charge capability:
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
  
  -- If no charge RN found, warn (but don't unassign—that's a gap)
  IF v_candidate.user_id IS NULL THEN
    v_warnings := array_append(v_warnings,
      'HARD CONSTRAINT: No charge-capable RN for ' || v_date || ' ' || v_shift_type);
  END IF;
END IF;
```

**Effect:** Every shift with RNs has charge coverage, or a warning is logged and a gap may result.

---

## Pass System Adjustments

### Pass 1: Full Soft Scoring
```
v_soft_weight_multiplier := 1.0;
v_request_override_allowed := FALSE;
```

### Pass 2: Relax Requests, Keep Soft Weights
```
v_soft_weight_multiplier := 1.0;
v_request_override_allowed := TRUE;
```

### Pass 3: Emergency (No Soft Weights)
```
v_soft_weight_multiplier := 0.0;
v_request_override_allowed := TRUE;
```

---

## Test Queries

### Find candidates who would violate cannot-be-2nd
```sql
SELECT
  u.name,
  u.cannot_be_second_rn_day,
  u.cannot_be_second_rn_night
FROM tmp_users u
WHERE u.cannot_be_second_rn_day = TRUE OR u.cannot_be_second_rn_night = TRUE;
```

### Find users at their pattern quota this week
```sql
SELECT
  u.name,
  t.week_start,
  t.target_count,
  wc.assigned_count,
  CASE
    WHEN wc.assigned_count >= t.target_count THEN 'At quota (reject further)'
    ELSE 'Below quota'
  END AS status
FROM tmp_users u
JOIN tmp_targets t ON t.user_id = u.user_id
JOIN tmp_week_counts wc ON wc.user_id = u.user_id AND wc.week_start = t.week_start
WHERE t.target_count IS NOT NULL
ORDER BY u.name, t.week_start;
```

### Find all gaps from hard constraint violations
```sql
SELECT
  date,
  shift_type,
  role_group,
  required_count,
  assignable_count,
  violation_reason
FROM tmp_hard_violations
ORDER BY date, shift_type, role_group;
```

---

## Summary: From Scoring to Enforcement

| Aspect | Old (Soft) | New (Hard) | Location |
|--------|-----------|-----------|----------|
| Pattern quota violation | Big penalty | WHERE constraint | `WHERE ... AND (t.target_count IS NULL OR wc.assigned_count < t.target_count)` |
| Cannot-be-2nd violation | Penalty, allowed | WHERE rejection | `WHERE ... AND NOT (v_assigned=1 AND cannot_be_second_*)` |
| Nights incapable | Penalty, soft | WHERE rejection | `WHERE ... AND (v_shift_type <> 'night' OR can_work_nights)` |
| Hard leave/sick | Penalty, overridable | WHERE rejection | `WHERE ... AND (r.value NOT IN ('L','S'))` |
| Role mismatch | Soft penalty | WHERE rejection | `WHERE ... AND ((role_group='rn' AND role_id IN (1,2)) OR ...)` |

**Bottom line:** Hard constraints moved from scoring into WHERE clause. No candidates pass through unless they're legal.

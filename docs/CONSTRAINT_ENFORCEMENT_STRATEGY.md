# Schedule Generator Constraint Enforcement Strategy

## Problem Identified
The current `generate_schedule_preview` function treats **all rules as soft penalties**. This means:
- Violations result in big scores, not rejection
- The solver can violate a rule if doing so lowers the total score elsewhere
- Pattern quotas are checked AFTER assignment (warnings only)
- Fallback passes explicitly allow breaking what should be "hard" rules

**Result:** Rules are routinely and silently violated.

---

## Solution: Hard vs Soft Constraint Separation

### Hard Constraints (NEVER violated, enforced in WHERE clause)

These are checked **during candidate selection**, not after:

#### A) Shift Legality
- RN: only LD or N allowed
- NA: only 8-8 or N allowed
- **Enforced:** Candidate must have compatible role
- **Failure:** Slot left empty, warning "no eligible shift type for role"

#### B) Nights Capability
- If `can_work_nights = false`, candidate cannot be assigned to N
- **Enforced:** WHERE checks `can_work_nights OR shift_type != night`
- **Failure:** Candidate rejected, may leave gap

#### C) Ward Minima (Coverage Floors)
- Per date, per role_group:
  - RN day: ≥ 2
  - RN night: ≥ 2
  - NA day: ≥ 3
  - NA night: ≥ 1
- **Enforced:** While loop continues until minima met; if no one assignable, gap
- **Failure:** Slot left empty; warning: "HARD CONSTRAINT GAP: [date] [shift] [role] - required N, got M"

#### D) Charge Coverage
- Every shift must have at least one eligible charge RN
- **Enforced:** After assignment, select 1st RN with `can_be_in_charge_*=true`
- **Failure:** Warning logged (hard failure, not silent)

#### E) Cannot-be-2nd RN
- If exactly 2 RNs on a shift:
  - Day: neither can have `cannot_be_second_rn_day = true`
  - Night: neither can have `cannot_be_second_rn_night = true`
- **Enforced:** WHERE clause checks on 2nd RN selection: `NOT (v_assigned=1 AND cannot_be_second_rn_*=true)`
- **Failure:** 2nd RN rejected; may leave gap

#### F) Weekly Pattern Quotas
- For each staff member and week:
  - Weekly targets must be exactly matched (or warn if exception needed)
  - Examples:
    - "2/week": exactly 2 shifts
    - "223" / "334": exact targets per week (anchored or not)
    - "1L1S": exactly 1 long + 1 short per week
- **Enforced:** WHERE clause prevents `assigned_count >= target_count`
- **Failure:** If week fills, staff can't be assigned; gap left; warning "PATTERN MISMATCH"

#### G) 1L1S Composition Enforcement
- Composition pattern staff must have exactly 1 long + 1 short per week
- **Enforced:** WHERE prevents assigning >2 shifts when pattern=composition
- **Failure:** Only 1 assignment possible; gap for 2nd; warning logged

---

### Soft Constraints (Scoring only, can be violated)

These influence the score but don't prevent assignment:

- **Fairness:** Previous period night/weekend counts (lower score if overdue for nights)
- **Preferences:** Shift clustering, night appetite, weekend appetite, leave adjacency
- **Recommended targets:** 3rd RN on day, 2nd NA on night (nice-to-have)
- **Anti-horror:** Recovery time from nights, oscillation penalties (soft but high weight)

**Application:** Soft constraints affect the `score` in the SELECT, not the WHERE clause.

**Pass adjustment:** `v_soft_weight_multiplier` can reduce soft scores in later passes.

---

## Pass System (No Pattern Breaking)

### Pass 1: Hard Constraints + Full Soft Scoring
- `v_soft_weight_multiplier = 1.0`
- `v_request_override_allowed = FALSE`
- Enforce: hard constraints, pattern quotas, legality, nights capability, cannot-be-second
- Score: full fairness/preference weights
- Assign: best-scoring candidates that satisfy all hard constraints
- Result: Optimal schedule respecting all rules; some slots may remain empty if unfillable

### Pass 2: Relax Request Strength Only (Still Enforce Hard)
- `v_soft_weight_multiplier = 1.0` (soft scores unchanged)
- `v_request_override_allowed = TRUE` (strong off requests downweighted but not blocked)
- Enforce: **all hard constraints remain, including patterns**
- Score: allow override of "strong off" requests only if needed to meet minima
- Assign: fill remaining gaps; log forced overrides
- Result: Coverage improved but no rule violations (only requests bent)

### Pass 3: Emergency Mode (Drop Soft Weights, Still Hard)
- `v_soft_weight_multiplier = 0.0` (fairness/preference weights zeroed)
- `v_request_override_allowed = TRUE`
- Enforce: **all hard constraints remain, including patterns**
- Score: no fairness/preference penalties; coverage prioritized
- Assign: fill remaining gaps with any eligible candidate
- Result: Maximum coverage; warnings logged for forced assignments

**Critical:** Never a pass that breaks patterns or legality.

---

## Debug Output & Transparency

### Per-User Pattern Tracking
For each user/week combo, the warning log includes:
```
PATTERN MISMATCH: [Name] week [N] - target [T], assigned [A]
```
This proves whether pattern targets were enforced.

### Hard Constraint Violations
For each gap left, a warning explains WHY:
```
HARD CONSTRAINT GAP: [date] [shift] [role] - required [N], got [M] 
(hard constraints made slot impossible)
```

### Forced Override Logging (Pass 2+)
```
FORCED OVERRIDE: [date] [Name] assigned despite strong off request
```

---

## Acceptance Criteria (Hard Stops)

A schedule is **valid** only if:

1. ✓ **No illegal shift types** (RN has LD or N only; NA has 8-8 or N only)
2. ✓ **No staff exceed weekly targets** (pattern quotas matched or explicitly noted as exception)
3. ✓ **1L1S staff have exactly 1 long + 1 short** per week (or gap left)
4. ✓ **Cannot-be-second RN never appears** in 2-RN pairs
5. ✓ **Every shift has charge coverage** (or gap explicitly flagged)
6. ✓ **Ward minima met or gaps documented** (RN ≥2/2, NA ≥3/1)

If **any** criteria fail → Generator **refuses output** or produces **explicit gaps** with warnings.

---

## Implementation Path

1. **Validate v2 function compiles & runs** on a test period
2. **Compare output** to current version:
   - Check for gaps where rules were previously violated
   - Verify pattern targets appear in warnings if not met
   - Confirm charge coverage logged
3. **Add switch in admin UI** to toggle `generate_schedule_preview` vs `v2`
4. **Test with known problem periods** (ones that always violate patterns)
5. **Migrate to v2** once stable

---

## Key Code Changes

### Shift Legality Check
```sql
-- Implicit: shift_code assigned based on role and shift_type
-- RN day → v_long_code (LD)
-- RN night → v_rn_night_code (N)
-- NA day → v_na_day_code (8-8)
-- NA night → v_na_night_code (N)
-- No other combinations possible in CASE logic
```

### Pattern Quota Enforcement
```sql
WHERE
  -- ...other conditions...
  AND (t.target_count IS NULL OR wc.assigned_count < t.target_count)
```

### Cannot-be-2nd Enforcement
```sql
WHERE
  -- ...other conditions...
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

### Charge Coverage Verification
```sql
IF v_assigned >= v_required THEN
  SELECT a.user_id
  FROM tmp_assignments a
  WHERE a.date = v_date
    AND a.shift_type = v_shift_type
    AND a.role_group = 'rn'
    AND ((v_shift_type = 'day' AND can_be_in_charge_day = TRUE)
      OR (v_shift_type = 'night' AND can_be_in_charge_night = TRUE))
  LIMIT 1;
  
  IF NOT FOUND THEN
    v_warnings := array_append(v_warnings, 'HARD CONSTRAINT: No charge-capable RN for ...');
  END IF;
END IF;
```

---

## Next Steps

1. Deploy v2 function to staging DB
2. Run preview on 2-3 periods that previously failed pattern checks
3. Compare warnings to current version
4. Verify no patterns violated in output
5. Prepare admin UI switch for toggling generators
6. Plan cutover to v2 as default

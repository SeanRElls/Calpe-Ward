# Scheduling Logic Specification: The Truth

**Status:** Authoritative reference for all generator implementations  
**Date:** 2026-01-20

This document defines the complete constraint model, pattern mathematics, and scheduling logic for Calpe Ward rota generation. **Any generator implementation that deviates from this specification is incorrect.**

---

## 1. Output Shape (Non-Negotiable)

**Generator output must be a complete 5-week layout exactly matching rota.html structure:**

- **Weeks 1–5** (fixed count)
- **Dates as rows**
- **Shift slots as columns**
- Each slot either:
  - Has an assigned staff name + shift code
  - Is a gap (explicitly marked with reason)

**Visual semantics must match rota.html:**
- Highlight gaps
- Show charge indicator
- Display shift codes correctly

**Return structure:**
```
rota_grid: JSONB (date → shifts array)
shifts_json: JSONB (flat list for analysis)
explanation_log: TEXT (decision reasoning)
period_score: INT (optimization metric)
total_shifts: INT (coverage count)
warnings: TEXT[] (constraint violations, gaps, forced overrides)
```

---

## 2. Hard Constraints vs Soft Constraints

### HARD CONSTRAINTS (Never Broken, Ever)

**If any hard constraint cannot be satisfied, the generator MUST:**
1. Leave a gap in the output
2. Log exactly which constraint made assignment impossible
3. Never "creatively solve" by violating a different hard constraint

**Hard constraint violations are production bugs.**

---

### HARD CONSTRAINT DEFINITIONS

#### A) Shift Legality by Staff Group

**Registered Nurses (role_id 1, 2):**
- Can only be assigned: **LD (12.5h)** or **N (12.5h)**
- Cannot be assigned: 8-8, W, or any NA shift type

**Nursing Assistants (role_id 3):**
- Can only be assigned: **8-8 (12h)** or **N (12h)**
- Cannot be assigned: LD, short shifts

**Short Shifts (8-5, 11-8):**
- **ONLY** for "1 long + 1 short" pattern staff (currently Paul)
- **ONLY** as the "short" component of their 2-shift week
- **NEVER** assigned to any other staff member

**Current v1 violation:**
- Assigns `8-8` to RNs when `requires_long = TRUE`
- This directly violates shift legality
- **Must be fixed:** RN + day → LD only, RN + night → N only

---

#### B) Nights Capability

**Rule:**
- If `can_work_nights = FALSE` → staff member **cannot** be assigned N shift, ever
- No exceptions, no "emergency override"

**Enforcement:**
- WHERE clause: `(shift_type <> 'night' OR can_work_nights = TRUE)`

---

#### C) Ward Minima Per Shift

**Per date, the generator must ensure:**

**Day shifts:**
- RN ≥ 2 (required minimum)
- RN = 3 (recommended, but not hard)
- NA ≥ 3 (required minimum)

**Night shifts:**
- RN ≥ 2 (required minimum)
- NA ≥ 1 (required minimum)
- NA = 2 (recommended, but realistically often not achieved)

**If minima cannot be met:**
- Produce a gap in output
- Warning: `"Ward minimum not met: [date] [shift_type] [role_group] - required N, got M"`
- **No "creative solutions"**

---

#### D) Charge Coverage Rules (Hard, Not Nice-to-Have)

**For each day shift and each night shift:**
- There **must** be a charge-designated RN
- Charge Nurses normally work days; nights should be irregular
- Some nurses cannot be in charge at all (`can_be_in_charge_day/night = FALSE`)

**Charge assignment priority (explicit hierarchy):**
1. Filter: eligible RNs for that shift type + can_work_nights check if night
2. Sort:
   - `role_id ASC` (Charge Nurse > Staff Nurse)
   - `display_order ASC` (rota order, top-down priority)
3. Choose: highest ranked eligible among assigned RNs

**Operational rule:**
> "Ideally the person in charge should be the highest up the list, only going down the order of the rota to meet requests and good off duty."

**This means:**
- Charge assignment is not "pick any eligible"
- It's rank-biased and should degrade only when requests force it

**If no charge-capable RN can be assigned:**
- Shift is functionally invalid
- Produce gap or re-select RNs to include charge-capable
- **Warning-only is not acceptable for production**

---

#### E) "Cannot Be Second RN" is Pair Feasibility (Not Just 2nd-Person Filter)

**Rule:**
- If a shift only has 2 RNs, **neither** can be a "must-be-3rd-only" nurse
- This is a **pair constraint**, not a single-person constraint

**Flags:**
- `cannot_be_second_rn_day` = TRUE → this RN cannot be in a 2-person day RN shift
- `cannot_be_second_rn_night` = TRUE → this RN cannot be in a 2-person night RN shift

**Enforcement must validate BOTH RNs:**
- When selecting 1st RN: if `required = 2`, exclude RNs with `cannot_be_second_rn_*` flag
- When selecting 2nd RN: exclude RNs with `cannot_be_second_rn_*` flag

**Current v1 violation:**
- Only checks 2nd RN
- Can accidentally pick flagged RN as 1st, then assign valid 2nd → pair still violates rule

**Correct logic:**
```
WHERE NOT (
  role_group = 'rn'
  AND assigned = 1  -- This is 2nd RN
  AND ((shift_type = 'day' AND cannot_be_second_rn_day = TRUE)
    OR (shift_type = 'night' AND cannot_be_second_rn_night = TRUE))
)
AND NOT (
  role_group = 'rn'
  AND assigned = 0  -- This is 1st RN
  AND required > 1  -- We'll be assigning 2 total
  AND ((shift_type = 'day' AND cannot_be_second_rn_day = TRUE)
    OR (shift_type = 'night' AND cannot_be_second_rn_night = TRUE))
)
```

---

#### F) Pattern Compliance is Hard for "Hard Patterns"

**Hard patterns:**
- 2 shifts/week (exact)
- 1 long + 1 short (exact, composition)
- 2/2/3 repeating (anchored cycle)
- 3/3/4 repeating (anchored cycle)

**Rule:**
- Generator **must never exceed** weekly pattern targets for hard patterns
- If it can't cover ward minima without violating a hard pattern, then it **must** show gaps and warn:
  - `"Coverage impossible under hard constraints: [reason]"`

**Current v1 violation:**
- Has "final fallback: allow exceeding targets" (+600 score penalty)
- This is **not allowed** under the hard constraint model
- Exceeding hard pattern targets is a constraint violation, not a "last resort"

**Enforcement:**
- WHERE clause: `(target_count IS NULL OR assigned_count < target_count)`
- No "relaxed pass" that removes this filter

---

#### G) 1 Long + 1 Short (Composition) is Exact

**For composition-pattern staff (currently Paul):**

**Per week:**
- Exactly **1 long** shift (LD)
- Exactly **1 short** shift (8-5 or 11-8)
- Total: exactly **2 shifts**

**Short assignment timing:**
- 8-5 on Mon-Wed
- 11-8 on Thu-Fri

**Exclusivity:**
- Short shifts **must never** be assigned to anyone else
- Composition staff should not get nights (business rule; generator currently enforces this)

**Tracking:**
- Must track `assigned_long` and `assigned_short` separately, not just `assigned_count`
- Validation: after generation, verify `assigned_long = 1 AND assigned_short = 1` per week

**Current v2 violation (in draft):**
- Never assigned short shifts at all
- Only enforced "max 2", not actual composition
- Counters declared but not updated

---

## 3. Patterns: The Part Copilot Glosses Over

**Pattern definitions are not "types", they are constraints with mathematics.**

### Database Structure (Must Use)

**Tables:**
- `pattern_definitions.weekly_targets[]` — array of target counts per cycle week
- `pattern_definitions.requires_anchor` — boolean, true for anchored cycles
- `user_patterns.anchor_week_start_date` — date, defines cycle phase for this staff member

### Anchored Patterns (3/3/4, 2/2/3)

**Weekly targets come from `weekly_targets[]` array.**

**The correct target for a given week depends on:**
- Where that staff member is in the cycle
- Determined by anchor alignment

**Anchor alignment formula (from v1, correct):**
```sql
(weekly_targets[
  ((
    (((week_start - (anchor_week_start_date - EXTRACT(dow FROM anchor_week_start_date)::int))) / 7)::int
  ) % array_length(weekly_targets,1) + array_length(weekly_targets,1)) % array_length(weekly_targets,1) + 1
])
```

**This is not optional.**  
If anchor math is wrong, the rota is wrong even if it "looks nice."

**Current v2 draft violation:**
- Hard-coded pattern targets (e.g., `WHEN pattern_type IN ('repeating') THEN 3`)
- Breaks anchored patterns completely
- Must use actual `weekly_targets` array + anchor alignment

---

### Nurse Flexible: 16 Shifts Over 5 Weeks (40h Staff)

**Pattern:**
- **Base:** 3 shifts in 4 of the weeks
- **One "extra" week:** 4 shifts
- **Total:** 16 shifts over 5 weeks

**The "extra" week should be chosen strategically:**
- Prioritize week(s) with more leave/unavailable requests
- Avoid weeks where staffing is already fine

**This is a constraint + strategy hybrid:**
- **Constraint:** total and per-week target must match the flexible plan
- **Strategy:** choose which week gets the extra based on demand

**Current v1 implementation:**
```sql
SELECT w.week_start INTO v_extra_week_start
FROM tmp_weeks w
LEFT JOIN tmp_requests r
  ON r.date >= w.week_start AND r.date < (w.week_start + 7)
  AND r.value IN ('L','S')
GROUP BY w.week_start
ORDER BY COUNT(r.*) DESC, w.week_start ASC
LIMIT 1;

-- Then:
CASE WHEN pattern_type = 'nurse_flexible_16_5w' THEN
  CASE WHEN w.week_start = v_extra_week_start THEN 4 ELSE 3 END
```

**This is correct.** v2 must preserve this logic.

---

## 4. Role Hierarchy and "In Charge" Selection

### Charge Ranking Logic (Explicit)

**When picking charge for a shift:**

1. **Eligible if:**
   - Charge flags match shift type (`can_be_in_charge_day` for day, `can_be_in_charge_night` for night)
   - Plus `can_work_nights = TRUE` if night shift

2. **Sort priority:**
   - `role_id ASC` (Charge Nurse = 1 > Staff Nurse = 2)
   - `display_order ASC` (rota order, top-down)

3. **Choose:**
   - Highest ranked eligible among the assigned RNs for that shift

**Additional soft constraint:**
- Two Charge Nurses (role_id 1) ideally on opposite patterns (minimize overlap)
- Occasional overlaps allowed but should be minimized in scoring

**Charge logic is separate from "who gets assigned at all":**
- But it must influence scoring too
- If generator assigns 2 RNs but neither can be charge → **that assignment set is invalid** for the shift

**Enforcement:**
- After RN minima met, verify at least one assigned RN is charge-capable
- If not, either:
  - Re-select to include charge-capable RN
  - Or leave gap + warning

---

## 5. Anti-Horror Rules (Soft Constraints with Strong Penalties)

**These are not "hard" because ward is small and reality is cruel.**  
**But they should be strong enough that generator avoids them unless forced.**

### Oscillation Avoidance

**Bad:**
- LD N LD N (frequent day/night alternation)

**Acceptable:**
- LD LD N
- LD LD LD N N

**Penalty:** Heavy score penalty for day-after-night assignment, especially immediate

### Recovery After Nights

**After nights, ideally:**
- Insert sleep day + full day off

**Example good:**
- N N N O O (3 nights, then 2 off)

**Penalty:** Score penalty for insufficient recovery after night runs

### Scoring Model

Anti-horror penalties should be strong enough to:
- Avoid oscillation unless required to meet minima
- Avoid day-after-night unless required to meet minima
- Prioritize recovery time after nights

**Current v1 penalties:**
```sql
-- Day after night (500 penalty):
WHEN shift_type = 'day' AND EXISTS (
  SELECT 1 FROM tmp_assignments a
  WHERE a.user_id = u.user_id AND a.date = (date - 1) AND a.shift_type = 'night'
) THEN 500

-- Oscillation (200 penalty):
WHEN EXISTS (
  SELECT 1 FROM tmp_assignments a1
  WHERE a1.user_id = u.user_id AND a1.date = (date - 1) AND a1.shift_type <> shift_type
) AND EXISTS (
  SELECT 1 FROM tmp_assignments a2
  WHERE a2.user_id = u.user_id AND a2.date = (date - 2) AND a2.shift_type = shift_type
) THEN 200
```

**These penalties are appropriate and should be preserved.**

---

## 6. Staff Preferences (1–5 are Inputs to Scoring, Not Rules)

**Preferences are weights, not constraints.**

### Preference List

**From staff table (`pref_*` columns):**

1. **Shift clustering** (`pref_shift_clustering`):
   - Higher = prefer shifts together
   - Lower = prefer shifts spread out

2. **Weekend preference** (`pref_weekend_appetite`):
   - 5 = wants max weekends
   - 3 = balanced
   - 1 = wants weekends off

3. **Nights appetite** (`pref_night_appetite`):
   - 5 = wants more nights
   - 3 = balanced
   - 1 = wants more days

4. **Leave adjacency** (`pref_leave_adjacency`):
   - Higher = wants off before/after leave blocks
   - Lower = indifferent

### Additional Preferences (Implicit)

5. **Willingness for 4 in a row** (if it creates more consecutive off days)
6. **Willingness for 5 in a row** (same condition)
7. **Rolling nights preference** (some like it, some don't)

### Preference Model

**Strong off requests (rank 1–2) are quasi-hard:**
- Should be treated as "avoid unless required to meet minima"
- Penalty: 1000 (very high, but not 99999)

**Normal off requests (rank 3–5):**
- Penalty: 200–400

**Specific shift requests (LD, N, 8-8, etc.):**
- Bonus: -50 (prefer this person for this shift type)

**Soft preferences (appetites):**
- Weight: 15 per preference point deviation
- Applied as: `(5 - pref_value) * 15`

---

## 7. Why Current v1 "Doesn't Acknowledge the Rules"

### Identified Violations

**1. RN shift legality violated:**
- v1 assigns `8-8` to RNs when `requires_long = TRUE`
- Directly contradicts hard constraint A
- **Fix:** RN + day → LD only, RN + night → N only

**2. Hard patterns aren't hard:**
- "Final fallback: allow exceeding targets" (+600 penalty)
- Violates hard constraint F
- **Fix:** Remove fallback that allows `assigned_count >= target_count`

**3. Charge coverage not enforced:**
- Checked after assignment, logged as warning
- If charge is hard, "no charge" means shift is invalid
- **Fix:** Validate charge-capable RN exists before finalizing RN assignments

**4. Cannot-be-second RN needs pair feasibility:**
- v1 only filters 2nd RN
- Can accidentally pick flagged RN as 1st
- **Fix:** Filter both 1st and 2nd RN selections when `required = 2`

**5. Patterns simplified:**
- Anchored cycle math is correct in v1 (good)
- But needs to be preserved in any refactor
- v2 draft broke this completely

---

## 8. The Exact Instruction for Any Generator Implementation

**Constraint-Satisfaction Scheduler Specification:**

You must treat this as a constraint-satisfaction scheduler with a fixed 5-week rota output grid identical to rota.html. Implement hard constraints as feasibility filters (never violate; leave gaps with explicit reasons), and soft constraints as scoring penalties.

**Hard constraints include:**
1. Role minima per shift (Day: RN≥2, NA≥3; Night: RN≥2, NA≥1)
2. Shift legality by staff group (RN: LD/N only; NA: 8-8/N only; short shifts only for 1L1S pattern staff)
3. Nights capability (`can_work_nights = FALSE` → no N shifts)
4. Charge coverage requirements (must have charge RN, ranked by role_id then display_order)
5. Cannot-be-second RN pair feasibility when only 2 RNs (check both RNs, not just 2nd)
6. Hard pattern weekly quotas for 2 shifts/week, 1L1S, 2/2/3, 3/3/4 (never exceed targets)

**Pattern targets must:**
- Come from `pattern_definitions.weekly_targets` with anchor alignment using `user_patterns.anchor_week_start_date`
- `nurse_flexible_16_5w` must place one 4-shift week chosen to cover high-leave weeks

**Charge nurse selection must:**
- Follow `role_id ASC` then `display_order ASC` priority
- "In charge" should ideally be the highest ranked eligible person
- Only move down the order as requests/constraints force

**Soft constraints include:**
1. Fairness vs previous period night/weekend counts
2. Preferences (1–5 appetite scales)
3. Avoiding LD/N oscillation
4. Recovery after nights (sleep day + full day off)

**Output must include:**
- `rota_grid` (date → shifts)
- `explanation_log` (decision reasoning)
- `warnings` (constraint violations, gaps, forced overrides)
- Must log when candidates are excluded due to shift legality or pattern rules

---

## 9. Summary: Hard vs Soft

| Constraint | Type | Violation Action | Relaxation Allowed? |
|-----------|------|------------------|---------------------|
| Shift legality (RN: LD/N; NA: 8-8/N) | Hard | Leave gap + warn | Never |
| Nights capability | Hard | Leave gap + warn | Never |
| Ward minima (RN≥2, NA≥3 day; RN≥2, NA≥1 night) | Hard | Leave gap + warn | Never |
| Charge coverage | Hard | Leave gap + warn or re-select | Never |
| Cannot-be-2nd RN pair | Hard | Exclude from selection | Never |
| Hard pattern targets (2/week, 1L1S, 2/2/3, 3/3/4) | Hard | Exclude from selection | Never |
| Anti-horror (oscillation, day-after-night) | Soft | Score penalty (500) | In emergency passes |
| Fairness (night/weekend counts) | Soft | Score penalty (2-10) | Always weighted |
| Preferences (appetites) | Soft | Score penalty (15/point) | Always weighted |
| Strong off requests | Quasi-hard | Score penalty (1000) | Only if minima require |

---

## 10. Generator Implementation Checklist

**Any generator claiming to implement this specification must:**

- [ ] Never assign RN to 8-8 or NA to LD
- [ ] Never assign N to `can_work_nights = FALSE` staff
- [ ] Never exceed hard pattern weekly targets (no "fallback override")
- [ ] Always validate charge coverage exists before finalizing RN assignments
- [ ] Check cannot-be-2nd pair feasibility (both RNs, not just 2nd)
- [ ] Use real `weekly_targets` array + anchor alignment for anchored patterns
- [ ] Choose flex week strategically for nurse_flexible_16_5w
- [ ] Track `assigned_long` and `assigned_short` separately for composition
- [ ] Assign short shifts (8-5, 11-8) only to composition staff
- [ ] Select charge by `role_id ASC, display_order ASC` priority
- [ ] Leave explicit gaps when hard constraints make assignment impossible
- [ ] Log warnings with specific constraint violation reasons
- [ ] Apply anti-horror penalties (500 for day-after-night, 200 for oscillation)
- [ ] Weight soft preferences by appetite scales (15/point)
- [ ] Produce output matching rota.html structure exactly

---

**This specification is the single source of truth for scheduling logic.**  
**Any implementation that deviates is incorrect by definition.**

**Last Updated:** 2026-01-20  
**Owned By:** Ward scheduling requirements  
**Enforced By:** All generator functions (v1, v2, future)

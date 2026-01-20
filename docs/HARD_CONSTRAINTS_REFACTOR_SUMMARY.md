# Schedule Generator Refactor: Hard Constraints Enforcement

## TL;DR

**Problem:** Current generator treats rules (patterns, coverage, legality) as **soft penalties**. It violates them silently if doing so lowers the total score.

**Solution:** New `generate_schedule_preview_v2` function **enforces hard constraints during candidate selection**, not after. Rules that would be violated → slot left **empty** with a warning explaining why.

---

## What Changed

### From (Old Approach)
```
Score candidate based on all factors (including penalties for rule violations)
→ Select best-scoring candidate
→ Log warnings if rules violated
→ Output schedule (violations included)
```

### To (New Approach)
```
SELECT candidates WHERE all hard constraints satisfied
→ Score soft constraints only (fairness, preferences)
→ Select best-scoring candidate that satisfies hard constraints
→ If no one qualifies → LEAVE SLOT EMPTY
→ Output schedule (gaps where rules made assignment impossible)
→ Log explicit reason for each gap
```

---

## Hard Constraints Now Enforced

| Constraint | Old | New | Result |
|---|---|---|---|
| **Shift legality** (RN: LD/N, NA: 8-8/N) | Penalty | WHERE clause | Illegal shifts impossible |
| **Nights capability** (can_work_nights) | Penalty | WHERE clause | Non-capable never assigned N |
| **Pattern quotas** (weekly targets) | Warning after | WHERE clause | Exceeding target = candidate rejected |
| **Cannot-be-2nd RN** | Penalty | WHERE clause (on 2nd selection) | Violation prevented at selection |
| **Charge coverage** | Warning after | Checked after; if missing = gap | Every shift has charge or documented gap |
| **Ward minima** (RN 2/2, NA 3/1) | Soft weight | While loop until met or gap | Minima met or gap left with reason |
| **1L1S composition** (1 long + 1 short) | Soft weight | WHERE clause | >2 assignments impossible |

---

## Pass System (Unchanged in concept, enforces hard now)

### Pass 1: Hard + Soft Scoring
- Enforce all hard constraints
- Full soft weights (fairness/preferences)
- Fill minima
- Result: Optimal schedule respecting rules; may have gaps

### Pass 2: Relax Request Strength Only
- **Still enforce all hard constraints**
- Allow "strong off" requests to be overridden if needed for minima
- Result: Coverage improved; forced overrides logged

### Pass 3: Emergency Mode
- **Still enforce all hard constraints**
- Drop soft weights (no fairness/preference penalties)
- Maximize coverage
- Result: Max coverage; all violations are hard constraint gaps (documented)

**Key:** No pass ever breaks patterns or legality.

---

## Output Changes

### Warnings Now Explain Why Slots Are Empty

**Old Output:**
```json
{
  "rota_grid": [
    {
      "date": "2026-01-21",
      "shifts": [
        {"assigned_user": "Paul", "role_group": "rn", "shift_type": "day"},
        {"assigned_user": "Sarah", "role_group": "rn", "shift_type": "day"}
      ]
    }
  ],
  "warnings": ["No suitable RN found"]
}
```

**New Output:**
```json
{
  "rota_grid": [
    {
      "date": "2026-01-21",
      "shifts": []
    }
  ],
  "warnings": [
    "HARD CONSTRAINT GAP: 2026-01-21 day rn - required 2, got 0 (hard constraints made slot impossible)",
    "PATTERN MISMATCH: Paul week 0 - target 2, assigned 1",
    "HARD CONSTRAINT: No charge-capable RN for 2026-01-21 day"
  ]
}
```

---

## Validation Examples

### Example 1: Pattern Quota Enforcement
**Setup:** Paul has pattern "2/week", week 1 is full (2 shifts assigned)

**Old:** Paul might get 3rd assignment if it lowered the overall score  
**New:** Paul rejected for 3rd assignment; warning: "PATTERN MISMATCH: Paul week 1 - target 2, assigned 3"

### Example 2: Cannot-be-2nd Enforcement
**Setup:** Jane has `cannot_be_second_rn_day=true`

**Old:** Jane might be selected as 2nd RN if it lowered score (big penalty but not blocking)  
**New:** Jane rejected as 2nd RN; candidate selection WHERE clause prevents it

### Example 3: Nights Capability
**Setup:** Bob has `can_work_nights=false`

**Old:** Bob might be assigned N if fairness needed him and penalty was worth it  
**New:** Bob never selected for N shifts; WHERE clause excludes him

### Example 4: Pattern Quota + Composition (1L1S)
**Setup:** Composition pattern staff must have exactly 1 long + 1 short per week

**Old:** Might get 2 longs or 2 shorts if score improved  
**New:** WHERE clause prevents >2 assignments; exactly 1L + 1S enforced (or gap)

---

## For the Brain (Your Decision Logic)

The key insight: **Don't score violations—prevent them.**

- **Old thinking:** "If this violates the rule, add a big penalty to the score"
- **New thinking:** "If this would violate the rule, don't let the candidate through WHERE clause"

This eliminates the calculus entirely. No more "does the penalty outweigh the benefit?" No more silent violations. Just: "Is this assignment legal?" If not, reject. If yes, score it on soft criteria.

---

## Deployment Checklist

- [ ] Create `generate_schedule_preview_v2` function (SQL file created)
- [ ] Deploy to staging; run test periods
- [ ] Validate warnings match constraints (testing guide provided)
- [ ] Compare to old version on same periods (gaps expected vs old violations)
- [ ] Once validated, create admin UI toggle to switch generators
- [ ] Set v2 as default; keep old version available for rollback
- [ ] Monitor warnings for correctness (update if new constraints found)
- [ ] After 1-2 weeks, decommission old version

---

## Questions?

- **Q:** Will schedules be less full (more gaps)?  
  **A:** Yes, initially. That's the point—better to show gaps where rules make it impossible than to silently violate rules.

- **Q:** Can soft constraints still be tuned?  
  **A:** Yes. Fairness weights, preference weights, anti-horror penalties can all be adjusted in the soft scoring WITHOUT breaking hard constraints.

- **Q:** What if we want to override a hard constraint?  
  **A:** That's future work. For now, hard = hard. If overrides needed (e.g., admin exception for pattern violation), we can add an "admin override mode" later.

- **Q:** Will the generator still respect fairness?  
  **A:** Yes. Fairness is soft, applied to scoring. If you're fair 90% of the time and hard constraints force unfairness 10% of the time, that's acceptable. The score will reflect it (lower overall score) but the constraint won't be violated.

---

## Reference Files

1. **SQL Function:** `sql/functions/generate_schedule_preview_v2_hardconstraints.sql`
2. **Strategy Doc:** `docs/CONSTRAINT_ENFORCEMENT_STRATEGY.md`
3. **Testing Guide:** `docs/TESTING_VALIDATION_GUIDE.md`
4. **This Summary:** `docs/HARD_CONSTRAINTS_REFACTOR_SUMMARY.md`

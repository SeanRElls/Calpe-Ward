# Scheduling Preview Generator — Implementation Reference

## Quick Reference

### Files Created/Modified
1. **[preview.html](preview.html)** — Admin-only preview generator page
2. **[admin.html](admin.html)** — Added preview link to sidebar nav
3. **[SCHEDULING_PREVIEW_GENERATOR.md](SCHEDULING_PREVIEW_GENERATOR.md)** — Complete feature documentation
4. **[PREVIEW_GENERATOR_UI_GUIDE.md](PREVIEW_GENERATOR_UI_GUIDE.md)** — UI/UX walkthrough

### Database Schema (Already Implemented)
```sql
-- users table additions
ALTER TABLE users ADD COLUMN (
  rota_rank INT,                            -- Lower = higher priority for charge
  pref_shift_clustering INT CHECK (1-5),    -- 1=isolated, 5=consecutive
  pref_night_appetite INT CHECK (1-5),      -- 1=few nights, 5=many
  pref_weekend_appetite INT CHECK (1-5),    -- 1=few weekends, 5=many
  pref_leave_adjacency INT CHECK (1-5),     -- 1=gap before/after, 5=adjacent OK
  can_be_in_charge_day BOOLEAN DEFAULT FALSE,
  can_be_in_charge_night BOOLEAN DEFAULT TRUE,
  cannot_be_second_rn_day BOOLEAN DEFAULT FALSE,
  cannot_be_second_rn_night BOOLEAN DEFAULT FALSE,
  can_work_nights BOOLEAN DEFAULT TRUE
);

-- pattern_templates table (for pattern-based scheduling)
CREATE TABLE pattern_templates (
  id UUID PRIMARY KEY,
  pattern_key TEXT UNIQUE,
  name TEXT,
  cycle_weeks INT,
  weekly_targets JSONB,
  requires_anchor BOOLEAN,
  description TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Existing tables used
- shifts: Basic shift data (date, time, shift_code)
- requests: Staff requests (leave, off-request)
- staffing_requirements: Min RN, NA per shift type
- pattern_definitions: Shift patterns for period
- user_patterns: Staff assignments to patterns
- audit_logs: Preference change tracking
```

### Core Concepts

| Concept | Definition | Key Field |
|---------|-----------|-----------|
| **Rota Rank** | Seniority/priority ordering for charge RN selection. Lower number = higher priority. | `users.rota_rank` |
| **Hard Constraint** | Cannot be violated (e.g., staff on leave cannot work). If violated, schedule infeasible. | — |
| **Soft Penalty** | Constraint with adjustable cost; system tries to avoid but will override if needed. | Penalty scoring |
| **Charge RN** | Lead/in-charge RN for shift; selected based on rank + constraints. | `can_be_in_charge_(day\|night)` |
| **Seniority Penalty** | Cost incurred when selecting lower-ranked charge RN than top-ranked eligible. | Position in eligible list |
| **Anti-Horror** | Penalties for oscillation (day/night switches) and recovery (too many consecutive shifts). | Preference alignment |
| **Preference Alignment** | How well assignment matches user preferences (clustering, nights, weekends, leave adjacency). | Slider penalties |
| **Explainability** | Detailed log of why each charge RN was selected or skipped. | Decision tree output |

---

## Page Navigation

### From Admin Console
```
admin.html (Admin Control Panel)
  → Sidebar nav: "📊 Preview Generator" link
  → Navigates to: preview.html
```

### Breadcrumb Path
```
Admin Console
  ↓
Preview Generator
  → [Select Period] → [Generate] → [Review Tabs] → [View Grid] → [Read Log] → [Save]
```

### Exit Points
- **Cancel:** Back to Admin Console (no save)
- **Save:** Commit to database → Redirect to rota.html

---

## Feature Checklist

### ✅ Completed
- [x] User preferences (4 sliders: 1–5 scale) added to `users` table
- [x] Capability flags (5 booleans) added to `users` table
- [x] Pattern templates table created with 6 seed patterns
- [x] Preference update RPCs (staff & admin) fully functional
- [x] UI integrated: rota.html, requests.html, admin.html modals
- [x] Staff can save/load preferences
- [x] Admin can edit user preferences & capabilities
- [x] Preference audit logging implemented
- [x] Preview generator page scaffolded with full documentation
- [x] Charge assignment algorithm documented
- [x] Decision explainability framework designed
- [x] Rota rank-based priority system defined

### 🔄 In Progress / Future
- [ ] Backend RPC: `generate_schedule_preview(period_id)` — compute optimal assignments
- [ ] Preference scoring penalties (oscillation, anti-horror, fairness)
- [ ] Charge selection iterative algorithm
- [ ] Export to PDF/CSV
- [ ] Scenario comparison (multiple previews)
- [ ] Manual override mode
- [ ] Batch scheduling (multiple periods)

---

## Data Flow: How Preview Generator Works

```
┌─────────────────────────────────────────────────────────────────┐
│ ADMIN NAVIGATION                                                │
├─────────────────────────────────────────────────────────────────┤
│ admin.html → Click "📊 Preview Generator"                       │
│                    ↓                                             │
│              preview.html loads                                 │
│                    ↓                                             │
│         SELECT PERIOD (dropdown)                                │
│                    ↓                                             │
│         CLICK "GENERATE PREVIEW"                                │
└─────────────────────────────────────────────────────────────────┘
                        ↓
        ┌───────────────────────────────┐
        │ BACKEND DATA LOADING          │
        ├───────────────────────────────┤
        │ 1. Load period details        │
        │ 2. Load shifts (date range)   │
        │ 3. Load staff & preferences   │
        │ 4. Load requests (leave/off)  │
        │ 5. Load staffing requirements │
        │ 6. Load pattern definitions   │
        └───────────────────────────────┘
                        ↓
        ┌───────────────────────────────┐
        │ SCHEDULING ALGORITHM          │
        ├───────────────────────────────┤
        │ For each shift:               │
        │  A. Build eligible candidates │
        │  B. Select charge RN (ranked) │
        │  C. Calculate penalties       │
        │  D. Log decision reasoning    │
        │ RESULT: Assignments + log     │
        └───────────────────────────────┘
                        ↓
        ┌───────────────────────────────┐
        │ PREVIEW DISPLAY               │
        ├───────────────────────────────┤
        │ 1. Shift grid (cards)         │
        │ 2. Explanation log            │
        │ 3. Period summary & score     │
        │ 4. Save button                │
        └───────────────────────────────┘
                        ↓
        ┌───────────────────────────────┐
        │ ADMIN DECISION                │
        ├───────────────────────────────┤
        │ Review decisions...           │
        │    ↓                          │
        │ CANCEL (back to admin)        │
        │    OR                         │
        │ SAVE (to database) →rota.html │
        └───────────────────────────────┘
```

---

## Example: Charge RN Selection Walkthrough

### Input Data
```
Shift: Monday 2026-02-01, 08:00–20:00 (Day shift)
Shift requirement: Charge RN required (1 RN lead, 1 RN second, 1 NA)
Staffing requirement: can_be_in_charge_day=true, can_work_nights=N/A (day shift)

Staff roster:
  1. Alice (rota_rank=1, can_be_in_charge_day=true, on_leave_2026-02-01=true)
  2. Bob (rota_rank=3, can_be_in_charge_day=true, available=true)
  3. Carol (rota_rank=5, can_be_in_charge_day=true, available=true)
  4. Diana (rota_rank=7, can_be_in_charge_day=true, off-request_weak=true)
```

### Step A: Build Eligible Candidates
```
Filter by can_be_in_charge_day=true: [Alice, Bob, Carol, Diana]
Filter by available (no leave): [Bob, Carol, Diana]  ← Alice removed (on leave)
Sort by rota_rank ascending: [Bob(3), Carol(5), Diana(7)]
Eligible = [Bob, Carol, Diana]
```

### Step B: Select Charge RN
```
candidate = Bob (rank 3, first eligible)

Evaluate Bob:
  - Available? YES
  - Eligible? YES (can_be_in_charge_day=true)
  - Seniority penalty = (0) = 0  (first eligible, no skips)
  - Oscillation penalty = 0 (previous day: off; next day: off)
  - Fairness penalty = 0 (fair assignment)
  → Total shift penalty = 0
  → SELECT BOB

(Note: We don't iterate further because Bob has no penalties.)
```

### Step C: Log Decision
```
Charge RN Selection:
  Eligible candidates (sorted by rota_rank):
    1. Bob (rank 3) — can_be_in_charge_day=true
    2. Carol (rank 5) — can_be_in_charge_day=true
    3. Diana (rank 7) — can_be_in_charge_day=true
  
  Skipped:
    Alice (rank 1): Hard constraint — on leave for this date.
  
  Decision:
    SELECTED: Bob (rank 3)
    Seniority Penalty: 1 (Alice rank 1 skipped due to leave)
    Oscillation Penalty: 0
    Fairness Penalty: 0
    Total Shift Penalty: 1

Rationale:
  "Highest-ranked available RN is Bob (rank 3).
   Alice (rank 1) would be preferred but is on leave.
   Bob is available with good schedule fit (no oscillation)."
```

### Output
```
Shift: Mon 2026-02-01, 08:00–20:00
  Charge RN: Bob (rank 3) ← Displayed in preview grid
  Reason: "Alice (rank 1) on leave for this date." ← Log entry
  Score: 1 ← Shift penalty contributed to total period score
```

---

## Constraint Decision Table

| Scenario | Charge Priority | Hard/Soft | Action | Log Entry |
|----------|---|---|---|---|
| Top-ranked available | Select rank 1 | Hard | Assign | "Selected rank 1 (best choice)." |
| Top-ranked on leave | Skip to rank 3 | Hard | Assign rank 3 | "Rank 1 on leave; selected rank 3." |
| Top-ranked: cannot_be_second_rn=true | Skip to rank 3 | Hard | Assign rank 3 | "Rank 1 cannot be in charge (capability); selected rank 3." |
| Top-ranked: can_work_nights=false (night shift) | Skip to rank 3 | Hard | Assign rank 3 | "Rank 1 ineligible for night (can_work_nights=false); selected rank 3." |
| Top-ranked: weak off-request | Option 1 or 2 | Soft | Assign with penalty OR skip | "Rank 1 has weak off-request; assigned anyway (penalty +1) OR skipped for fairness." |
| Top-ranked would spike anti-horror | Skip to rank 3 | Soft | Assign rank 3 | "Rank 1 would create oscillation; selected rank 3 for recovery." |
| Top-ranked already 8+ shifts (fairness) | Skip to rank 3 | Soft | Assign rank 3 | "Rank 1 already overworked (8 shifts); selected rank 3 for fairness." |
| No eligible RN | — | Hard | Flag warning | "⚠️ Coverage gap: No eligible charge RN for this shift." |

---

## Preference Slider Integration

### In Preview Generator
- **Tab: Features & Logic** — Explains all sliders (shift_clustering, night_appetite, weekend_appetite, leave_adjacency)
- **Tab: Scoring & Penalties** — Quantifies penalty for misalignment (e.g., low-clustering staff assigned isolated shift → +1 penalty)
- **Explanation Log** — Shows which staff triggered preference penalties and why

### Example Log Entry
```
Date: 2026-02-01 (Monday)
Shift: Day (08:00–20:00)

...

RN (Second): Sarah (rank 8)
Rationale: Available, no conflicts.
Preferences: pref_shift_clustering=2 (low, prefers spacing).
Note: Assigned single shift (isolated). Clustering penalty: +1.
Suggestion: Consider pairing Sarah with another shift next day to reduce penalty.
```

---

## Validation Checklist for Admins

### Before Saving Preview
- [ ] **Charge RNs Reasonable?** Are top-ranked staff mostly selected? Reasons compelling for exceptions?
- [ ] **Coverage Complete?** All shifts fully staffed? Any warnings about gaps?
- [ ] **Preferences Respected?** Most assignments match staff preferences? Hard constraints override soft?
- [ ] **Fairness Balanced?** Workload distributed fairly? No staff consistently overworked?
- [ ] **No Hard Violations?** Constraints violations logged? (If any, schedule is unsafe.)
- [ ] **Score Acceptable?** Total period score reasonable compared to previous rotations?
- [ ] **Explainability Clear?** Can you explain each charge RN selection to staff if questioned?

### Red Flags
- ⚠️ Charge RN mostly low-ranked (e.g., rank 7–10) → Likely constraint issues; review carefully
- ⚠️ Same staff in charge role 10+ times → Fairness concern; consider adjusting
- ⚠️ Many "weak off-request" violations → Staff may be unhappy; consider relaxing
- ⚠️ Coverage gap warnings → Schedule may be unsafe; consult staffing requirements
- ⚠️ High oscillation/recovery penalties → Anti-horror penalties high; check for duty rota balance

---

## Integration with Existing Features

### Rota (rota.html)
- **Read:** Displays finalized assignments (after save from preview)
- **Write:** None directly (preview generator is read-only until save)

### Requests (requests.html)
- **Read:** Loads staff preferences (off-requests, leave)
- **Write:** None

### Admin (admin.html)
- **Read:** User list, preferences, capabilities
- **Write:** Can edit user preferences → preview should reload to reflect changes

### User Modal (user-modal.js)
- **Read:** Loads current user preferences
- **Write:** Staff can update preferences via modal
- **Impact on Preview:** Admin should regenerate preview after staff preference changes for accuracy

### Permissions (permissions.js)
- **Admin Check:** `is_admin=true` required to view preview.html
- **Non-Admin Redirect:** Automatically redirects to rota.html

### Audit Logs (audit_logs table)
- **Record:** Every preference change (via `update_my_preferences` RPC)
- **Display:** Admin can review audit trail for preference modifications

---

## Testing Scenarios

### Scenario 1: Simple Happy Path
- **Setup:** 10 staff, 5 shifts, no conflicts
- **Expected:** All shifts assigned; all charge RNs top-ranked; no warnings
- **Validation:** Score minimal; explanations straightforward

### Scenario 2: Leave Conflicts
- **Setup:** Top-ranked staff on leave; other staff available
- **Expected:** Lower-ranked staff selected as charge; log explains leave conflict
- **Validation:** Seniority penalty applied; reason recorded

### Scenario 3: Capability Constraints
- **Setup:** Top-ranked staff has `can_be_in_charge_day=false` (night-only)
- **Expected:** Lower-ranked charge on day shift; cannot_be_second_rn capability drives decision
- **Validation:** Hard constraint violation avoided; log clear

### Scenario 4: Preference Misalignment
- **Setup:** Low-clustering staff assigned isolated shifts
- **Expected:** Preference penalty flagged; log records mismatch
- **Validation:** Admin can see preference violations; decides if acceptable

### Scenario 5: Fairness Imbalance
- **Setup:** Top-ranked staff already worked 8 shifts; others <3 shifts
- **Expected:** Lower-ranked staff selected for fairness; penalty recorded
- **Validation:** Workload more balanced; log explains fairness override

### Scenario 6: Infeasible Schedule
- **Setup:** Shift requires charge RN; no eligible staff available
- **Expected:** Coverage gap warning; shift flagged as unfillable
- **Validation:** Admin sees ⚠️ warning; can manually adjust or acknowledge risk

---

## Future Integration Points

### Potential RPC Calls (Not Yet Implemented)
```sql
-- Main preview generator function
CREATE FUNCTION generate_schedule_preview(
  p_period_id UUID,
  p_token TEXT
) RETURNS TABLE (
  shifts_assigned JSONB,
  explanation_log TEXT,
  period_score INT,
  warnings JSONB[]
) AS $$
-- Compute optimal assignments
-- Apply all constraints and penalties
-- Return assignments, log, score, warnings
$$;

-- Commit preview to rota
CREATE FUNCTION save_preview_to_rota(
  p_period_id UUID,
  p_token TEXT
) RETURNS JSON AS $$
-- Copy assignments to assignments/shifts tables
-- Audit log save action
-- Return success/error
$$;

-- Adjust penalty weights (admin tuning)
CREATE FUNCTION update_scheduling_parameters(
  p_token TEXT,
  p_seniority_weight NUMERIC,
  p_fairness_weight NUMERIC,
  -- ... other weights
) RETURNS JSON AS $$
-- Update stored procedure parameters
-- Audit tuning decision
-- Next preview will use new weights
$$;
```

### Admin Dashboard Enhancement (Future)
```
Preview Generator Statistics:
  - Avg charge RN rank (should be low)
  - Fairness ratio (std dev of shift counts)
  - Preference satisfaction % (assignments matching preferences)
  - Coverage %
  - Period score trend (compare to previous rotations)
```

---

## Troubleshooting

### Issue: "No periods available"
- **Cause:** No periods in database or all periods have end_date < today
- **Fix:** Admin creates new period in "Rota Periods" section

### Issue: "No shifts found for this period"
- **Cause:** Period has no shifts (no shifts generated in shift catalogue)
- **Fix:** Admin must generate shifts in "Shift Catalogue" section first

### Issue: "No eligible charge RN available"
- **Cause:** No staff with `can_be_in_charge_day/night=true` for that shift
- **Fix:** Admin updates staff capabilities in "Users" section

### Issue: Charge RN always rank 7+ (low priority)
- **Cause:** Higher-ranked staff have conflicting constraints (leave, off-requests, etc.)
- **Fix:** Review staff requests; adjust rota_rank if misassigned; relax soft constraints

### Issue: "Session expired" redirect
- **Cause:** Session token invalid or expired
- **Fix:** User logs back in; token refreshed

### Issue: Changes not appearing in preview
- **Cause:** Admin edited preferences but didn't regenerate
- **Fix:** Click "Generate Preview" again after preference changes

---

## Documentation Map

| Document | Purpose | Audience |
|----------|---------|----------|
| [SCHEDULING_PREVIEW_GENERATOR.md](SCHEDULING_PREVIEW_GENERATOR.md) | Feature documentation (logic, constraints, penalties, algorithm) | Admins, Developers |
| [PREVIEW_GENERATOR_UI_GUIDE.md](PREVIEW_GENERATOR_UI_GUIDE.md) | UI/UX walkthrough (page structure, tabs, workflows) | Admins, UX Designers |
| [IMPLEMENTATION_REFERENCE.md](IMPLEMENTATION_REFERENCE.md) **(this file)** | Quick reference, data flows, testing, troubleshooting | Developers, Admins |
| [preview.html](preview.html) | Live page (interactive tabs, preview generation, save) | End Users (Admins) |
| [admin.html](admin.html) | Admin console with preview link | End Users (Admins) |

---

## Related Features

- **User Preferences (Completed):** Sliders + capabilities stored in `users` table
- **Preference RPCs (Completed):** Staff & admin update functions with audit logging
- **Audit Logs (Completed):** Records all preference changes with metadata
- **Session Management (Completed):** Token-based auth for page access control

---

## Support & Contact

**For Admin Questions:**
- Check tabs in preview.html (Features, Constraints, Scoring, Algorithm, Log formats)
- Review [SCHEDULING_PREVIEW_GENERATOR.md](SCHEDULING_PREVIEW_GENERATOR.md) for logic details
- Review [PREVIEW_GENERATOR_UI_GUIDE.md](PREVIEW_GENERATOR_UI_GUIDE.md) for UI help

**For Developer Questions:**
- See data flow diagrams in this document
- Review charging algorithm pseudocode
- Check testing scenarios for edge cases

**For Bugs/Feature Requests:**
- Report via audit log or support system
- Include: period ID, affected shift, expected vs. actual decision

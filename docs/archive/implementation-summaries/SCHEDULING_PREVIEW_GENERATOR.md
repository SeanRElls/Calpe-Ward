# Scheduling Preview Generator — Complete Feature Documentation

## Overview

The **Scheduling Preview Generator** (`preview.html`) is an admin-only tool that provides complete visibility into how the ward scheduling system makes decisions. It documents all constraints, penalties, and decision logic, and then generates a preview schedule showing:

1. **What shifts are assigned to whom**
2. **Why each charge RN was selected** (with rank, seniority reasoning, constraint violations)
3. **How preferences and capabilities influenced decisions**
4. **Which constraints were applied and why**
5. **Confidence/fairness scores for each shift**

---

## Key Features

### 1. **Charge RN Selection with Rank-Based Priority**

**Goal:** Assign the highest-ranked (most senior) eligible RN as "in charge" for each shift, respecting hard constraints.

**How it works:**

- **Rota Rank Definition:** Lower `rota_rank` = higher seniority and priority for charge roles.
- **Eligible List:** System builds list of all RNs able to work that shift:
  - `can_be_in_charge_day` or `can_be_in_charge_night` = true (depending on shift type)
  - Not on leave, not with strong off-request
  - `can_work_nights` = true (if night shift)
  - No `cannot_be_second_rn` conflict for the charge slot
- **Rank Ordering:** Candidates sorted by `rota_rank` ascending (rank 1 first, then 3, 5, etc.)
- **Selection:** Choose top-ranked candidate unless:
  - **Hard constraint blocks them** (unavailable, off-request, capability mismatch)
  - **Severe penalty avoidance** (e.g., selecting lower rank avoids oscillation spike)

**Example:**

```
Shift: Monday 08:00–20:00 (Day)
Eligible Charge RNs: [Alice(rank 1), Bob(rank 3), Carol(rank 5)]

Decision Tree:
  → Alice (rank 1): Strong off-request for Mon. BLOCKED.
  → Bob (rank 3): Available, no conflicts. Seniority penalty if skip = 1. SELECTED.
  → Carol (rank 5): Not evaluated (Bob suitable).

Log Entry: "Selected Bob (rank 3) as charge. Reason: rank 1 (Alice) unavailable (strong off-request)."
```

---

### 2. **Hard Constraints (Must Be Met)**

#### Constraint A: Charge RN Presence
- **Rule:** Every shift requiring "in charge" coverage must have at least one RN with `can_be_in_charge_(day|night)` = true.
- **Violation:** If no charge-capable RN is available, rota is infeasible; warning logged.
- **Priority:** Hard (non-negotiable).

#### Constraint B: Staff Availability
- **Rule:** Staff member must not have:
  - Leave booked for that date
  - Unavailable flag set
  - **Strong** off-request (hard constraint)
  - **Weak** off-request (soft penalty; system tries to avoid but will use if needed)
- **Priority:** Hard for unavailable/leave/strong off-request; soft for weak off-request.

#### Constraint C: Cannot-Be-Second RN
- **Rule:** If staff has `cannot_be_second_rn_day` or `cannot_be_second_rn_night` = true, they cannot occupy the "second RN" slot for that shift type.
- **Rationale:** Protects high-rank staff from being relegated to subordinate roles.
- **Priority:** Hard.

#### Constraint D: Night Eligibility
- **Rule:** Staff with `can_work_nights` = false cannot work night shifts.
- **Default:** `can_work_nights` = true (most staff work nights).
- **Priority:** Hard.

#### Constraint E: Role & Skill Matching
- **Rule:** Staff role (RN, NA, etc.) must match shift requirement.
- **Staffing Requirement:** `staffing_requirements` table defines min RN, min NA per shift type.
- **Priority:** Hard.

---

### 3. **Soft Constraints & Preferences (Penalties)**

#### Penalty A: Charge Seniority
- **Definition:** If selected charge RN is not the top-ranked eligible person, apply penalty proportional to how far down the list.
- **Formula:** `penalty = (actual_rank_position - 1) * base_weight`
- **Example:**
  - Eligible: [rank 1, rank 3, rank 5]
  - Selected rank 1 → no penalty
  - Selected rank 3 → penalty ≈ 1–2 (one person skipped)
  - Selected rank 5 → penalty ≈ 2–3 (two people skipped)
- **Rationale:** Nudges system toward top-ranked staff unless constraints force otherwise.

#### Penalty B: Off-Requests (Weak)
- **Definition:** Assigning staff despite weak off-request incurs penalty.
- **Formula:** `penalty = weak_off_request_base_weight` (e.g., 1–2 points)
- **Rationale:** System respects preferences but overrides if needed; logs reason.

#### Penalty C: Shift Clustering Preference
- **Slider:** `pref_shift_clustering` (1–5)
  - 1 = prefers isolated shifts (days off between work)
  - 3 = neutral
  - 5 = prefers consecutive shifts (blocks of work)
- **Logic:**
  - Low-clustering staff assigned isolated shift → penalty ✓
  - High-clustering staff assigned alternating shifts → penalty ✓
  - Preference-aligned assignment → no penalty

#### Penalty D: Night Appetite
- **Slider:** `pref_night_appetite` (1–5)
  - 1 = few nights preferred
  - 3 = neutral
  - 5 = many nights preferred
- **Logic:**
  - Low-appetite staff assigned many nights → penalty
  - High-appetite staff assigned few nights → penalty
  - Preference-aligned → no penalty

#### Penalty E: Weekend Appetite
- **Slider:** `pref_weekend_appetite` (1–5)
  - 1 = few weekends preferred
  - 3 = neutral
  - 5 = many weekends preferred
- **Logic:** Similar to night appetite.

#### Penalty F: Leave Adjacency
- **Slider:** `pref_leave_adjacency` (1–5)
  - 1 = staff prefers separation (gap before/after leave)
  - 3 = neutral
  - 5 = comfortable with shifts next to leave
- **Logic:**
  - Low-adjacency staff with shift next to leave → penalty
  - High-adjacency staff with gap → no penalty

#### Penalty G: Anti-Horror (Oscillation & Recovery)
- **Oscillation:** Rapid day/night switching penalized.
  - Working day, then night, then day → penalty
  - Encourages multi-day stretches.
- **Recovery:** Too many consecutive shifts without break → penalty.
  - Protects staff welfare; forces rotation.

#### Penalty H: Fairness (Optional/Future)
- **Concept:** Track shift counts per staff across period.
- **Logic:** Over-assign to already-busy staff → penalty.
- **Status:** Can be added later (currently soft version implemented).

---

### 4. **Charge Assignment Decision Algorithm**

```
FOR each shift requiring charge coverage:

  STEP A: Build Eligible Candidates
  ─────────────────────────────────
    Load all staff
    Filter by: can_be_in_charge_(day|night) = true
    Filter by: available (no leave, strong off-request)
    Filter by: not violating cannot_be_second_rn
    Sort by: rota_rank ascending (lowest = highest priority)
    Eligible = sorted list

  STEP B: Iterative Selection
  ──────────────────────────
    candidate = eligible[0]  // Top-ranked
    if candidate is hard-constrained (unavailable/blocked):
      candidate = eligible[1]  // Try next
      ...continue until suitable
    
    for each higher_ranked in eligible:
      if higher_ranked SKIPPED and NOT hard-constrained:
        record reason (e.g., "off-request", "anti-horror", "fairness")

  STEP C: Penalty Calculation
  ──────────────────────────
    seniority_penalty = (position_in_list - 0) * weight
    // e.g., position 0 → penalty 0; position 1 → penalty ~1–2
    
    // Add other penalties (off-request, oscillation, fairness, etc.)
    total_shift_penalty = seniority_penalty + other_penalties

  STEP D: Log Decision
  ───────────────────
    record {
      shift_id,
      selected_charge_rn,
      charge_rn_rank,
      was_first_choice: (position == 0),
      skipped_candidates: [
        {rank, name, skip_reason},
        ...
      ],
      total_penalty,
      constraint_status: "OK" | "WARNING" | "VIOLATED"
    }

END FOR
```

---

### 5. **Explainability Log Output**

For each shift, the log includes:

#### Basic Info
- Date, shift code (e.g., "Day", "Night")
- Staffing requirement (e.g., "2 RN, 1 NA")
- Whether charge required

#### Charge RN Decision
```
Charge RN Selection:
  Eligible candidates (by rank):
    1. Alice (rank 1)
    2. Bob (rank 3)
    3. Carol (rank 5)
  
  Decision:
    Alice: SKIP — Strong off-request for this date.
    Bob: SELECT — Available, no conflicts. Seniority penalty: 1.
    
  Selected: Bob (rank 3)
  Reason: Higher-ranked Alice unavailable.
```

#### Other RN Assignments
```
RN (Second):
  Assigned: Sarah (rank 8)
  Rationale: Available, no conflicts.
  Preferences: Shift clustering = 2 (low preference).
  Note: Assigned single shift (isolated). Clustering penalty: +1.
```

#### Shift Score Summary
```
Shift Score Breakdown:
  + Seniority penalty: 1
  + Preference penalty (Sarah clustering): 1
  + Coverage: OK (2 RN ✓, 1 NA ✓)
  ─────────────────────
  Total Shift Score: 2
```

#### Period Summary
```
PERIOD TOTALS
═════════════════════════════════════════════
Total Shifts Generated: 14
Total Schedule Score: 28
Coverage Status: Fully staffed ✓
Hard Constraint Violations: None
Warnings: 1 (Sarah assigned to isolated shift; prefers clustering)
```

---

## How to Use the Preview Generator

### Step 1: Navigate to Preview
- Log in as admin
- Click **"📊 Preview Generator"** link in admin sidebar (`admin.html`)

### Step 2: Select Period
- Choose a rota period from dropdown
- Click **"Generate Preview"**

### Step 3: Review Documentation Tabs
1. **Features & Logic:** Overview of system capabilities and user preferences.
2. **Constraints:** Hard and soft constraints explained.
3. **Scoring & Penalties:** How penalties are calculated.
4. **Charge Assignment Algorithm:** Step-by-step decision tree.
5. **Decision Explanation Log:** How to interpret the log output.

### Step 4: Generate Schedule
- System loads shifts, staff, requests, staffing requirements, patterns
- Computes optimal assignments
- Displays generated schedule with charge RN selections

### Step 5: Review Shift Grid & Log
- **Shift Grid:** Each shift shows assigned staff, charge RN, rank, and reasoning.
- **Explanation Log:** Full details for every decision (eligible candidates, penalties, skipped reasons).

### Step 6: Validate Decisions
- Check charge RN selections: Are they reasonable given constraints?
- Spot fairness issues: Are some staff consistently busy/underused?
- Verify constraint compliance: Are violations explained?
- Respect preferences: Do most assignments align with user preferences?

### Step 7: Save to Rota (if satisfied)
- Click **"Save to Rota"**
- Confirm action (cannot be undone)
- Redirects to `rota.html` with assignments applied

---

## Technical Architecture

### Database Tables
- **users:** `rota_rank`, `pref_shift_clustering`, `pref_night_appetite`, `pref_weekend_appetite`, `pref_leave_adjacency`, `can_be_in_charge_day`, `can_be_in_charge_night`, `cannot_be_second_rn_day`, `cannot_be_second_rn_night`, `can_work_nights`
- **shifts:** Basic shift data (date, time, code)
- **requests:** Staff requests (leave, off-request)
- **staffing_requirements:** Min RN, NA per shift type
- **pattern_definitions:** Shift patterns for period planning
- **user_patterns:** Staff assignment to patterns
- **audit_logs:** Tracks all preference changes and admin actions

### Frontend (`preview.html`)
- **Tabbed UI:** Features, Constraints, Scoring, Algorithm, Explanation Log
- **Read-only Display:** No edit controls (preview only)
- **Interactive Tabs:** Switch between documentation and generated schedule
- **Print-friendly CSS:** Styled for printing/PDF export

### Backend (future RPC)
- **generate_schedule_preview(period_id):** Computes optimal assignments
  - Loads shifts, staff, requests
  - Applies constraints and penalties
  - Returns: assignments, scores, explanation log
- **save_preview_to_rota(period_id):** Commits preview to database

---

## Example Decision Scenarios

### Scenario 1: Standard Selection
```
Shift: Monday 08:00–20:00 (Day, Charge Required)
Eligible Charge RNs: [Alice(1), Bob(3)]

Result: Alice selected (rank 1)
Reason: Top-ranked, available, no conflicts
Seniority Penalty: 0 (first choice)
```

### Scenario 2: Skipping Higher-Ranked
```
Shift: Tuesday 20:00–08:00 (Night, Charge Required)
Eligible Charge RNs: [Alice(1), Bob(3), Carol(5)]

Constraints:
  - Alice: can_work_nights = false
  - Bob: Available
  - Carol: Available

Result: Bob selected (rank 3)
Reason: Alice ineligible (cannot work nights); Bob next available
Seniority Penalty: 1 (Alice skipped due to hard constraint)
```

### Scenario 3: Fairness Override
```
Shift: Wednesday 08:00–20:00 (Day, Charge Required)
Eligible Charge RNs: [Alice(1), Bob(3)]

Constraints:
  - Alice: Charge assignment 8 times already this period (high)
  - Bob: Charge assignment 2 times already this period (low)

Result: Bob selected (rank 3)
Reason: Fairness penalty prevented Alice selection despite higher rank
Seniority Penalty: 2 (Alice skipped for fairness)
```

---

## User Preferences & Capability Flags Reference

| Preference | Type | Range | Meaning |
|------------|------|-------|---------|
| `pref_shift_clustering` | Slider | 1–5 | 1=isolated shifts; 5=consecutive shifts |
| `pref_night_appetite` | Slider | 1–5 | 1=few nights; 5=many nights |
| `pref_weekend_appetite` | Slider | 1–5 | 1=few weekends; 5=many weekends |
| `pref_leave_adjacency` | Slider | 1–5 | 1=gap before/after leave; 5=comfortable next to leave |
| `can_be_in_charge_day` | Boolean | true/false | Can lead day shifts |
| `can_be_in_charge_night` | Boolean | true/false | Can lead night shifts |
| `cannot_be_second_rn_day` | Boolean | true/false | Cannot be second RN on day shift |
| `cannot_be_second_rn_night` | Boolean | true/false | Cannot be second RN on night shift |
| `can_work_nights` | Boolean | true/false | Eligible for night shifts (default true) |

---

## Validating Schedule Quality

Use the explanation log to answer:

1. **Charge RN Choices:** Are top-ranked staff consistently chosen? If not, are reasons clear?
2. **Fairness:** Is workload distributed? Check if some staff dominate charge roles.
3. **Constraints Met:** Are hard constraints never violated? Are soft constraints mostly respected?
4. **Preferences Honored:** Do staff get shifts matching their preferences? (Note: hard constraints override soft preferences.)
5. **Coverage:** Are all shifts fully staffed? Any gaps or warnings?

---

## Next Steps (Future Enhancements)

1. **Fairness Tracking:** Add shift count balancing across period.
2. **Pattern Optimization:** Automatically enforce staffing patterns (e.g., rotating weekends).
3. **Export & Comparison:** Generate multiple preview scenarios; export to PDF.
4. **Batch Scheduling:** Apply preview to multiple periods at once.
5. **Manual Override:** Allow admin to manually adjust assignments; system recalculates penalties.

---

## See Also

- [User Preferences Guide](CELL_HISTORY_FEATURE_GUIDE.md) (for preference sliders overview)
- [Security Migration](SECURITY_MIGRATION_READY_TO_RUN.sql) (session tokens & permissions)
- [Architecture Overview](docs/architecture/override-system.md) (constraint system design)

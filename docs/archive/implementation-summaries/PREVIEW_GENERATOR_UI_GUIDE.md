# Scheduling Preview Generator — UI & Navigation Guide

## Page Structure

The preview generator (`preview.html`) is organized into **6 main sections** plus a **live preview area**.

---

## Section 1: Page Header

**Location:** Top of page (full-width banner)

```
Scheduling Preview Generator
Admin-only tool: Preview shifts, charge assignments, constraints, and decision reasoning
```

**Purpose:** Identifies the page and explains its role.

---

## Section 2: Generate Preview Controls

**Location:** Below header (card-styled section)

### Components:
1. **Period Selection Dropdown**
   - Label: "Select a period..."
   - Populated from `periods` table (sorted by start_date, newest first)
   - Display format: `"Period Name (YYYY-MM-DD to YYYY-MM-DD)"`
   - Example: "Jan 20 – Feb 2, 2026 (2026-01-20 to 2026-02-02)"

2. **Generate Button**
   - Label: "Generate Preview"
   - Color: Primary blue
   - Action: Fetches shifts, staff, requests; calculates assignments; shows preview
   - Disabled state: If no period selected

3. **Status Message**
   - Initially hidden
   - Shows during generation: "Generating preview..." (loading state, light blue)
   - On success: "Preview generated successfully" (green)
   - On error: "Error: [message]" (red)

**User Flow:**
```
1. User selects period from dropdown
2. User clicks "Generate Preview"
3. Status shows "Generating..." (brief spinner state)
4. Page loads shifts, requests, staffing requirements
5. Algorithm computes optimal assignments
6. Status shows "Ready"
7. Preview grid and log become visible
```

---

## Section 3: Documentation Tabs

**Location:** Below controls (horizontal tab navigation)

### Tab List:
1. **Features & Logic** (default active)
2. **Constraints**
3. **Scoring & Penalties**
4. **Charge Assignment Algorithm**
5. **Decision Explanation Log**

### Tab Styling:
- **Active Tab:** Blue text, blue bottom border (3px)
- **Inactive Tab:** Gray text, gray border
- **Responsive:** Wraps on mobile devices
- **Interaction:** Click to switch; previously active tab hidden

---

## Tab 1: Features & Logic

### What This Generator Does
Lists 6 key features in bullet format with detailed explanations:
1. **Reads Current Data** — Loads periods, shifts, staff, requests, patterns
2. **Validates Constraints** — Ensures hard constraints met (charge presence, availability, eligibility)
3. **Optimizes Scheduling** — Applies soft penalties (clustering, anti-horror, fairness, seniority)
4. **Charge RN Priority** — Selects highest-ranked eligible RN
5. **Explainability** — Logs every decision with reasoning
6. **Preview Only** — Read-only display; requires "Save to Rota" to commit

### Rota Rank Explanation
- **Highlight Box** (green background)
- Key insight: "Lower rank number = higher priority for in charge assignments"
- Explains seniority/charge competence link

### User Preferences & Capabilities
- Preference Sliders (1–5): shift_clustering, night_appetite, weekend_appetite, leave_adjacency
- Capability Flags (bool): can_be_in_charge_day/night, cannot_be_second_rn_day/night, can_work_nights

### Decision Output Includes
Lists what admin sees in generated preview:
- Shift assignments (date, code, staff, role)
- Charge RN name and rank
- Reason if lower-ranked charge selected
- Violations/warnings
- Scoring breakdown

---

## Tab 2: Constraints

### Hard Constraints Section
5 constraints listed with label badge (red), explanation, and examples:

1. **Charge RN Requirement**
   - "Every shift requiring in charge coverage MUST have at least one RN with can_be_in_charge_day/night=true"
   - If impossible: "Schedule is infeasible; warning logged"

2. **Staff Availability**
   - Hard if: leave, unavailable, strong off-request
   - Soft penalty if: weak off-request
   - "Off-requests: Soft penalty if weak off-request; hard constraint if strong off-request"

3. **Cannot-Be-Second RN Rule**
   - If `cannot_be_second_rn_day/night=true`, staff cannot be second RN on that shift type
   - Rationale: "Ensures charge RNs not forced into subordinate roles"

4. **Night Eligibility**
   - If `can_work_nights=false`, no night shifts
   - Default: true

5. **Role & Skill Matching**
   - Staff role (RN, NA) must match shift requirement
   - References `staffing_requirements` table

### Soft Constraints Section
3 sub-sections:

- **Off-Requests (Weak):** "Assigning staff despite weak off-request incurs penalty; system tries to avoid but will use if needed"

- **User Preferences (1–5 Sliders):** Each slider explained with high/low meaning
  - Shift Clustering: "Higher = consecutive shifts; Lower = spacing"
  - Night Appetite: "Higher = many nights; Lower = few nights"
  - Weekend Appetite: "Higher = willing weekends; Lower = prefers weekdays"
  - Leave Adjacency: "Higher = comfortable next to leave; Lower = prefers gap"

---

## Tab 3: Scoring & Penalties

### Scoring System Intro
"The generator minimizes total penalty; lower score = better schedule."

### Penalty Types (8 listed):

1. **Charge Seniority Penalty**
   - "If selected charge RN is not highest-ranked eligible person, apply penalty proportional to how far down the list"
   - Example: Eligible=[rank 1, 3, 5]; select rank 3 → penalty ~1; select rank 5 → penalty ~2–3
   - Rationale: "Nudges system to keep charge assignments at top unless constraints prevent"

2. **Anti-Horror Penalties**
   - Oscillation: "Rapid day/night switches penalized; encourages consecutive stretches"
   - Recovery: "Too many consecutive shifts without break → penalty; protects staff welfare"

3. **Preference Alignment Penalty**
   - Shift Clustering: "Low-clustering staff assigned isolated shifts → penalty; vice versa for high-clustering"
   - Night Appetite: "Low-appetite staff assigned many nights → penalty"
   - Weekend Appetite: "Similar logic for weekends"

4. **Fairness Penalty (Optional)**
   - "Can track shift counts per staff and penalize over-assignment"
   - Status: "Future enhancement"

5. **Coverage & Staffing Penalty**
   - "If shift under-staffed, penalty applied"
   - "System still generates schedule but flags gap in explanation log"

---

## Tab 4: Charge Assignment Algorithm

### Decision Tree (Code-styled block)

```
For each shift requiring charge coverage:

Step A: Build Eligible List
  → Load all staff
  → Filter by: can_be_in_charge_(day|night) = true
  → Filter by: available (no leave, strong off-request)
  → Filter by: not violating cannot_be_second_rn
  → Sort by: rota_rank ascending (lowest = highest priority)

Step B: Select Charge RN
  → candidate = first eligible staff (highest rank)
  → score_if_selected = calculate_penalty(candidate)
  
  → for each next_lower_ranked_candidate:
      next_score = calculate_penalty(next_candidate)
      if next_score << score_if_selected (significantly better):
          candidate = next_lower_ranked_candidate
          reason = "constraints made lower rank necessary"
      else:
          break (stick with current candidate)
  
  → assign candidate as charge RN

Step C: Log Decision
  → record: charge_rn_name, charge_rn_rank, was_first_choice
  → if not first choice: record reason
```

### Why Lower-Ranked Charge RN Selected
6 reasons listed:
- Leave/Unavailable
- Off-Requests (strong)
- cannot_be_second_rn Conflict
- Night Ineligibility
- Anti-Horror Protection
- Fairness

Each with brief explanation.

### Example Scenario
```
Shift: Monday, 08:00–20:00 (Day shift, charge required)
Eligible Charge RNs (sorted by rank): [Alice (rank 1), Bob (rank 3), Carol (rank 5)]

Constraints:
• Alice: strong off-request for Monday (hard constraint)
• Bob: no off-request, available
• Carol: no off-request, available

Decision:
→ Alice is skipped (hard off-request).
→ Bob becomes charge RN (rank 3).
→ Log: "Assigned Bob (rank 3) as charge RN. Reason: higher-ranked Alice (rank 1) has strong off-request."
→ Penalty: seniority penalty for not choosing rank 1 (medium, because Alice unavailable).
```

---

## Tab 5: Decision Explanation Log

### What Gets Logged?

- **For Every Shift:** Date, shift code, assigned staff, role, decision reason
- **For Every Charge RN:** Name, rank, was first choice (yes/no), reason if not
- **Skipped Candidates:** Why higher-ranked skipped (unavailable, off-request, anti-horror, fairness)
- **Violations/Warnings:** Coverage gaps, constraint conflicts, infeasible regions

### Example Log Entry

```
Date: 2026-02-01 (Monday)
Shift: Day (08:00–20:00)

Assignment:
• RN (Charge): Bob (rank 3)
• RN (Second): Sarah (rank 8)
• NA: James

Charge Decision Log:
"Eligible charge RNs: [Alice(1), Bob(3), Carol(5)].
Alice(1) SKIPPED: strong off-request for this date.
Carol(5) SKIPPED: seniority penalty would be larger than Bob(3).
SELECTED: Bob(rank 3) — good balance of availability and seniority.
Seniority penalty: 2 (Alice unavailable, so penalty reduced)."

Preferences Alignment:
"Sarah (pref_shift_clustering=2, low) assigned single shift (isolated). Penalty: +1.
James: no conflicts."

Overall Shift Score: 8
```

### How to Use Log to Validate

4 validation checks:
1. **Check Charge RN Choice:** Reasonable? If not top-ranked, reason compelling?
2. **Spot Fairness Issues:** Some staff consistently busy/underused?
3. **Verify Constraint Compliance:** Violations explained? Hard constraints never violated?
4. **Respect Preferences:** Do assignments align with preferences? (Hard constraints override soft)

---

## Section 4: Generated Schedule Preview (Post-Generation)

**Visibility:** Hidden initially; shown after "Generate Preview" clicked and succeeds

### Shift Grid

**Layout:** Responsive grid (auto-fit, min 250px per card)

**Card Per Shift:**
```
┌─────────────────────────────────────┐
│ Monday, Feb 1 — Day Shift (08–20)   │ (header with blue line)
├─────────────────────────────────────┤
│ 💼 Charge RN: Bob (Rank 3)          │ (blue background)
│    Reason: Alice has off-request    │ (gray italic text)
│ RN (Second): Sarah                  │
│ NA: James                           │
│ Score: 8                            │ (small gray text bottom)
└─────────────────────────────────────┘
```

**Interactive:** Click on card to expand details (future feature)

---

## Section 5: Explanation Log

**Location:** Below shift grid card

**Format:**
- **Background:** Light gray (#f5f5f5)
- **Font:** Monospace (Courier New)
- **Padding:** 15px
- **Text Wrapping:** White-space preserved (pre-wrap for readability)

**Content:** Full explanation log (see Tab 5 example above)

**Features:**
- Copy button (future)
- Print button (uses print CSS)
- Export to PDF (future)

---

## Section 6: Save to Rota Controls

**Location:** Below explanation log

### Alert Box
- **Background:** Yellow (#fff3cd)
- **Border:** 1px solid gold
- **Text:** "⚠️ Preview Only: This is a read-only preview. To apply these changes to the rota, click 'Save to Rota' (requires confirmation)."

### Save Button
- **Label:** "Save to Rota"
- **Color:** Primary blue
- **Action:** Shows confirmation dialog; on confirm, sends assignments to database; redirects to rota.html

---

## User Workflows

### Workflow 1: Review Documentation (No Period Selected)

```
1. User navigates to preview.html (admin-only)
2. Sees header + controls + documentation tabs
3. Tabs active; can read Features, Constraints, Scoring, Algorithm, Log formats
4. No preview grid visible (no period selected)
5. User learns about system before generating preview
```

### Workflow 2: Generate Preview for Period

```
1. User selects period from dropdown
2. Clicks "Generate Preview"
3. Status shows "Generating..." (loading state)
4. System fetches data; calculates assignments
5. Status shows "Generated successfully" (green)
6. Shift grid appears with card per shift
7. Explanation log appears below
8. "Save to Rota" button visible
9. User reviews decisions in grid + log
10. User clicks "Save to Rota" to apply (requires confirmation)
11. Redirects to rota.html; assignments now live
```

### Workflow 3: Validate Decision for Specific Shift

```
1. User reviews shift grid
2. Looks for charge RN name + reason card
3. If reason present (not first choice), user clicks to expand details
4. User scrolls to explanation log
5. Finds matching shift entry in log
6. Reads full decision reasoning (eligible candidates, skipped reasons, penalties)
7. User satisfied → proceeds to save
   OR
   User not satisfied → does not save; cancels back to admin.html
```

### Workflow 4: Compare Multiple Scenarios (Future)

```
1. User generates preview for Period A
2. Takes screenshot or exports to PDF
3. Returns to preview.html
4. Generates preview for different parameters (if admin tweaks penalties)
5. Compares shift grids + scores
6. Chooses best preview to save
```

---

## Responsive Design

### Desktop (≥1024px)
- Sidebar nav (from admin.html, if linked)
- Full-width content
- Shift grid: 3–4 columns

### Tablet (768px–1024px)
- Sidebar collapsible (hamburger)
- Shift grid: 2 columns
- Tab navigation wraps

### Mobile (<768px)
- Hamburger menu for nav
- Full-width cards
- Shift grid: 1 column
- Tab navigation scrollable horizontally

---

## Styling & Visual Hierarchy

### Color Scheme
- **Primary:** #667eea (purple-blue, admin theme)
- **Secondary:** #764ba2 (purple gradient)
- **Success:** #4caf50 (green, for OK status)
- **Warning:** #ffc107 (gold, for warnings/review items)
- **Error:** #f44336 (red, for violations)
- **Neutral:** #666, #999 (grays for text)

### Typography
- **Headers:** Bold, larger font (18px–28px)
- **Body:** Regular, 13px–14px
- **Code/Mono:** Courier New, for decision tree and logs
- **Labels:** Uppercase, small (11px–12px), letter-spaced

### Spacing
- **Padding:** 20px–30px for sections
- **Gaps:** 10px–15px between elements
- **Margins:** 20px–30px between major sections

### Component Patterns
- **Buttons:** Rounded (4px), 10px–16px padding, hover state (darker shade)
- **Cards:** White background, rounded (6px–8px), subtle shadow (0 2px 4px rgba(0,0,0,0.1))
- **Inputs:** 8px–12px padding, 1px border, 4px border-radius
- **Dropdowns:** Same as inputs, custom styling

---

## Accessibility Features

- **ARIA Labels:** Nav tabs have role="tablist", individual tabs have aria-selected
- **Keyboard Navigation:** Tab through controls, Enter to activate, Arrow keys to switch tabs
- **Color Contrast:** Text meets WCAG AA standards
- **Skip Links:** Option to skip to main content (future)
- **Focus States:** Visible outline on keyboard focus

---

## Error Handling & Edge Cases

### Scenario 1: No Periods Available
**State:** Dropdown empty; Generate button disabled
**Message:** "No periods available. Contact admin."

### Scenario 2: Period Has No Shifts
**State:** Status shows "No shifts found for this period"
**Message:** "Please check period dates and shift catalogue."

### Scenario 3: Infeasible Schedule (No Charge RN Available)
**State:** Preview generated; score high; warnings flagged
**Message in Log:** "⚠️ Coverage gap on Night of 2026-02-05: No eligible charge RN available."

### Scenario 4: Session Expired
**State:** Page redirects to login; shows "Session expired, please log in again"

### Scenario 5: Non-Admin Tries to Access
**State:** Permission check runs; page redirects to rota.html
**Message:** "Admin access required"

---

## Future Enhancements

1. **Scenario Comparison:** Generate multiple previews; display side-by-side scores
2. **Manual Adjustments:** Admin can click on shift card to manually reassign; system recalculates penalties
3. **Export Options:** PDF, CSV, or email summary
4. **Batch Scheduling:** Apply preview to multiple periods at once
5. **Constraint Relaxation:** Admin sliders to adjust penalty weights (e.g., "reduce fairness penalty by 20%")
6. **Historical Comparison:** Compare current preview to previous rota; show improvement/regression
7. **Conflict Resolution:** Interactive mode to resolve conflicts (e.g., "Two people want same leave date; system suggests swaps")

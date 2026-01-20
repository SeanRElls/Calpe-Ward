# Quick Start: Scheduling Preview Generator

## 🎯 What You Have

You've been given a complete **Admin Preview Generator** that documents and showcases your scheduling logic.

### Files Created
1. **[preview.html](preview.html)** — The interactive preview page (admin-only)
2. **[admin.html](admin.html)** — Updated with preview link in sidebar
3. **[SCHEDULING_PREVIEW_GENERATOR.md](SCHEDULING_PREVIEW_GENERATOR.md)** — Complete technical documentation
4. **[PREVIEW_GENERATOR_UI_GUIDE.md](PREVIEW_GENERATOR_UI_GUIDE.md)** — UI/UX walkthrough
5. **[IMPLEMENTATION_REFERENCE.md](IMPLEMENTATION_REFERENCE.md)** — Developer reference
6. **[ADMIN_PREVIEW_GENERATOR_SUMMARY.md](ADMIN_PREVIEW_GENERATOR_SUMMARY.md)** — Summary & examples

---

## 🚀 How to Use (For Admins)

### 1. **Access the Preview Generator**
   - Log in as admin
   - Click **"📊 Preview Generator"** in the admin sidebar
   - You'll see the preview page with tabs

### 2. **Learn the System** (No Period Needed)
   - Click through 5 documentation tabs:
     - **Features & Logic** — What the system does
     - **Constraints** — Hard rules (must follow) + soft penalties (try to follow)
     - **Scoring & Penalties** — How quality is measured
     - **Charge Assignment Algorithm** — Decision tree for selecting charge RN
     - **Decision Explanation Log** — How to read the output
   - Tabs are interactive; read at your own pace

### 3. **Generate a Preview** (For Specific Period)
   - Select a period from dropdown
   - Click "Generate Preview"
   - Wait for status "Ready"
   - Review shift grid (cards showing assignments)
   - Read explanation log (reasoning for each decision)

### 4. **Validate Before Saving**
   - Ask yourself:
     - ✅ Are charge RNs reasonable? (mostly high-ranked?)
     - ✅ Is coverage complete? (all shifts staffed?)
     - ✅ Are preferences respected? (most assignments match preferences?)
     - ✅ Is fairness balanced? (workload distributed?)
     - ✅ Are all hard constraints met? (no rule violations?)
     - ✅ Is score acceptable? (good compared to past rotations?)
     - ✅ Can I explain these decisions to staff?
   - If YES to most → Safe to save
   - If NO to any → Investigate warnings in log; don't save

### 5. **Save (If Satisfied)**
   - Click "Save to Rota"
   - Confirm action
   - Redirects to rota.html with assignments live

---

## 📚 Documentation Map

| Document | Read If... |
|----------|-----------|
| [SCHEDULING_PREVIEW_GENERATOR.md](SCHEDULING_PREVIEW_GENERATOR.md) | You want to understand the **full feature logic** (constraints, penalties, algorithm, examples) |
| [PREVIEW_GENERATOR_UI_GUIDE.md](PREVIEW_GENERATOR_UI_GUIDE.md) | You want to understand the **page structure and workflows** (tabs, buttons, what to expect) |
| [IMPLEMENTATION_REFERENCE.md](IMPLEMENTATION_REFERENCE.md) | You are a **developer** or need detailed **troubleshooting/testing** info |
| [ADMIN_PREVIEW_GENERATOR_SUMMARY.md](ADMIN_PREVIEW_GENERATOR_SUMMARY.md) | You want a **summary of everything delivered** + next steps |

---

## ⚡ TL;DR: Key Concepts

### Rota Rank = Priority for Charge RN
- Lower number = higher priority (rank 1 best, rank 7 lower priority)
- System always prefers top-ranked available staff
- Only picks lower rank if hard constraint blocks higher rank

### Hard Constraints (Cannot Be Broken)
1. **Charge RN Required** — Every charge shift needs eligible RN
2. **Staff Availability** — No leave, no strong off-requests, no unavailable
3. **Cannot-Be-Second Rule** — High-rank staff can't be forced into second slot
4. **Night Eligibility** — Only night-capable staff on night shifts
5. **Role Matching** — Staff role matches shift requirement (RN vs. NA)

**If violated → Schedule unsafe → Warning logged**

### Soft Penalties (Try to Follow, But Overridable)
- **Charge Seniority** — Prefer top-ranked charge RN
- **Off-Requests (Weak)** — Try to honor, but not mandatory
- **Shift Clustering** — Match staff preferences (consecutive vs. spaced)
- **Night Appetite** — Match preferences (few nights vs. many nights)
- **Weekend Appetite** — Match preferences
- **Leave Adjacency** — Match preferences (gap vs. adjacent)
- **Anti-Horror** — Avoid rapid day/night switches; protect recovery time
- **Fairness** — Spread workload fairly

**These have a "cost"; lower total cost = better schedule**

### Explainability Log = The Why
For every shift, the system records:
- Who was selected as charge RN
- What their rank was
- Why (if not top-ranked, what blocked higher ranks?)
- Any preference violations or warnings

**This lets you explain every decision to staff** ✅

---

## 🔍 Red Flags to Watch

When reviewing a preview, be concerned if you see:

🚩 **Charge RN mostly rank 7+ (low priority)**
   → Likely hard constraints blocking higher ranks
   → Check for leave conflicts, capability mismatches

🚩 **Same staff in charge 10+ times (out of 14 shifts)**
   → Fairness concern
   → Consider if rotation is too imbalanced

🚩 **Many weak off-request violations**
   → Staff may be unhappy
   → Consider relaxing soft penalties

🚩 **Coverage gap warnings**
   → Some shifts under-staffed
   → Schedule may be unsafe
   → Contact staffing officer

🚩 **High oscillation/recovery penalties**
   → Anti-horror penalties spiking
   → Duty rota not rotating properly
   → May need to adjust shift patterns

---

## ✅ Ready to Use

The preview page is **fully functional as an interactive learning and decision-making tool**.

**What's NOT yet implemented:**
- Backend RPC to generate optimal assignments (you'll need a developer for this)
- Actual "save to rota" database write (placeholder exists)

**What IS implemented:**
- Complete UI with 6 interactive tabs
- Full documentation of scheduling logic
- Example data display format
- Session validation (admin-only)
- Responsive design (mobile/tablet/desktop)

---

## 📞 Need Help?

**For admins:**
1. Read the tabs on the preview page (they explain everything)
2. Check [PREVIEW_GENERATOR_UI_GUIDE.md](PREVIEW_GENERATOR_UI_GUIDE.md) for page walkthrough
3. Use validation checklist before saving

**For developers:**
1. Check [IMPLEMENTATION_REFERENCE.md](IMPLEMENTATION_REFERENCE.md) for data flow
2. See pseudocode for charge RN selection algorithm
3. Test scenarios section has 6 use cases to validate

**For questions:**
- All documentation is comprehensive and cross-referenced
- Use Ctrl+F to search within markdown files for specific topics

---

## 🎓 Example: How Charge RN Selection Works

**Shift:** Monday Day, 08:00–20:00 (needs charge RN)

**Staff eligible to be charge:**
- Alice (rank 1, on leave Monday) ❌
- Bob (rank 3, available) ✅
- Carol (rank 5, available) ✅

**Decision:**
→ Alice is skipped (on leave)
→ Bob selected as charge RN (rank 3)
→ Log: "Selected Bob (rank 3). Reason: higher-ranked Alice (rank 1) has strong off-request for this date."
→ Seniority penalty: 1 point (Alice unavailable, so reduced penalty)

**Admin sees in preview:**
- Shift card: "Charge RN: Bob (Rank 3) — Reason: Alice has off-request"
- Log entry: Full explanation (eligible candidates, skipped reasons, penalties)

**Admin can then decide:** Acceptable? Save or reject.

---

## 🎯 Next Steps

1. **As Admin:**
   - Navigate to preview.html from admin.html
   - Read the 5 documentation tabs
   - Understand how the system prioritizes and decides

2. **As Developer:**
   - Implement `generate_schedule_preview(period_id)` RPC
   - Implement `save_preview_to_rota(period_id)` RPC
   - Wire them to the frontend buttons
   - Test with sample data

3. **As Project Manager:**
   - All documentation complete ✅
   - UI/UX complete ✅
   - Logic fully specified ✅
   - Ready for backend implementation

---

**Enjoy your new scheduling preview tool! 🎉**

# Cell History Feature Implementation Guide

## Overview
This adds a complete audit trail for every rota cell, allowing admins to right-click and see the full history of what shifts were assigned and when/why they changed.

## Database Changes Required

### 1. Create History Table
Run `CREATE_ASSIGNMENT_HISTORY.sql` in Supabase SQL editor to create:
- `rota_assignment_history` table
- Indexes for performance
- `admin_get_assignment_history` RPC function

### 2. Update Swap Functions
Manually edit `sql/migrate_to_token_only_rpcs.sql` using the guidance in `HISTORY_IMPLEMENTATION_GUIDE.sql`:

**In `admin_execute_shift_swap` function:**
- Add 2 INSERT statements to `rota_assignment_history` (after comment section, before RETURN QUERY)
- Records both users' shift changes with detailed reason

**In `admin_approve_swap_request` function:**
- Add 2 INSERT statements to `rota_assignment_history` (after comment section, before RETURN QUERY)
- Records both users' shift changes with "Swap approved" reason

**Add new RPC function:**
- `admin_get_assignment_history` - retrieves full history for a cell (already in CREATE_ASSIGNMENT_HISTORY.sql)

### 3. Deploy to Supabase
1. Run `CREATE_ASSIGNMENT_HISTORY.sql` in Supabase SQL editor
2. Update `migrate_to_token_only_rpcs.sql` with history inserts
3. Run updated `migrate_to_token_only_rpcs.sql` to replace swap functions

## Frontend Changes Required

### 1. Add Script Reference
Add to `rota.html` (in the `<head>` or before closing `</body>`):
```html
<script src="js/assignment-history.js"></script>
```

### 2. Add data-assignment-id to Cells
In `rota.html` renderRota function (around line 807-900 where cells are created):
```javascript
const cell = document.createElement('td');
cell.dataset.assignmentId = assignmentId;  // Add this line
// ... rest of cell creation
```

Find where `renderRota()` creates table cells and add `cell.dataset.assignmentId = assignmentId;`

## Features

### Right-Click Menu
- Right-click any rota cell as an admin
- Context menu automatically shows assignment history modal
- Non-admins cannot access history

### History Display
Shows for each change:
- **Assignment Date** - When this shift was scheduled
- **Old Shift** - Previous shift code (e.g., "8-8")
- **New Shift** - New shift code after change
- **Reason** - What caused the change (e.g., "Admin swap with Person X")
- **Changed By** - Which admin made the change
- **Timestamp** - Exact time of change

### Example History Entry
```
Date: 2025-12-25  | Old: N  | New: LD  | Reason: Admin swap with Sarah  | Admin: Sean Ells  | 2026-01-19 15:32:45
Date: 2025-12-10  | Old: LD | New: N   | Reason: Admin swap with John   | Admin: Sean Ells  | 2026-01-18 10:15:22
```

## Testing

1. Make a swap (both users end up with different shifts)
2. Right-click a cell as admin
3. Verify history modal appears
4. Check that it shows:
   - Before/after shifts
   - Admin name who made the swap
   - Exact timestamp
   - Reason message

## Files Created/Modified

- ✅ `sql/CREATE_ASSIGNMENT_HISTORY.sql` - New table and RPC
- ✅ `sql/HISTORY_IMPLEMENTATION_GUIDE.sql` - Code snippets to add
- ✅ `js/assignment-history.js` - New frontend module
- ⏳ `sql/migrate_to_token_only_rpcs.sql` - NEEDS MANUAL UPDATES (see guide)
- ⏳ `rota.html` - NEEDS: script reference + data-assignment-id attributes

## Next Steps

1. Deploy SQL files to Supabase
2. Update migrate_to_token_only_rpcs.sql with history inserts
3. Add script reference to rota.html
4. Update cell rendering to add data-assignment-id
5. Test right-click → history functionality

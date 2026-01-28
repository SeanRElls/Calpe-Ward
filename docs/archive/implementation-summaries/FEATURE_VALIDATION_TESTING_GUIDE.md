# Feature Validation & Testing Guide
**Calpe Ward Post-Codex Security Migration**

---

## 🧪 Feature Testing Checklist

### PUBLISHED SHIFTS WORKFLOW ✅

#### Pre-Requisite
- [ ] Login successfully
- [ ] Navigate to rota.html
- [ ] Select a published period from dropdown

#### Test Cases

**1. Load Published Period Data**
- [ ] Period loads without errors
- [ ] Shift cells display with data
- [ ] User names visible in rows
- [ ] Date headers show correct dates
- Browser console: No RPC errors

**2. Click Published Shift Cell**
- [ ] Click on any shift cell
- [ ] Published details modal opens
- [ ] Assignment ID displays
- [ ] Shift information shows
- [ ] Expected: `openPublishedDetails` function executes

**3. View Published Comments**
- [ ] In published details modal, click "View Comments" button
- [ ] Comments load from database
- [ ] Comment author and date display
- [ ] Multiple comments show if present
- [ ] Expected: `rpc_get_rota_assignment_comments` RPC called with correct params:
  ```json
  {
    "p_assignment_ids": [assignment_id],
    "p_token": "current_session_token"
  }
  ```

**4. Add Comment to Published Shift**
- [ ] In details modal, type comment text
- [ ] Select visibility (all_staff, admin only)
- [ ] Click "Add Comment" button
- [ ] New comment appears in list
- [ ] Comment saved to database
- [ ] Expected: `rpc_add_rota_assignment_comment` RPC called with:
  ```json
  {
    "p_token": "session_token",
    "p_assignment_id": assignment_id,
    "p_comment": "comment_text",
    "p_comment_visibility": "all_staff"
  }
  ```

**5. Delete Published Comment**
- [ ] In details modal, find existing comment
- [ ] Click delete button on comment
- [ ] Comment removed from display
- [ ] Comment deleted from database
- [ ] Expected: `rpc_delete_rota_assignment_comment` RPC called with:
  ```json
  {
    "p_token": "session_token",
    "p_comment_id": comment_id
  }
  ```

**6. View Assignment History**
- [ ] In details modal, click "View History"
- [ ] Historical entries load
- [ ] Shows previous shifts and dates
- [ ] Changes recorded correctly

**7. View Override Information**
- [ ] If override exists, displays with:
  - [ ] Override hours
  - [ ] Override comment
  - [ ] Visibility level

---

### DRAFT PERIOD WORKFLOW ✅

#### Pre-Requisite
- [ ] Login successfully
- [ ] Select a draft period from dropdown
- [ ] Admin or has draft-edit permission

#### Test Cases

**1. Enter Edit Mode**
- [ ] Toggle "Editing" button in toolbar
- [ ] Button changes to show edit mode is active
- [ ] Blue metadata banner appears: "Draft Editing Mode..."
- [ ] All cells become clickable

**2. Open Shift Picker**
- [ ] Click any unassigned cell
- [ ] Shift picker modal opens
- [ ] Modal title shows assignment details
- [ ] Expected: Shift picker receives data
- [ ] Browser console: No errors about undefined `shifts`

**3. Select Shift from Picker**
- [ ] Modal shows available shifts
- [ ] All shifts in shift_catalogue load
- [ ] Shift codes, labels, colors visible
- [ ] Click to select a shift
- [ ] Expected: `shifts` global variable has data

**4. Save Draft Assignment**
- [ ] After selecting shift, cell updates
- [ ] New shift displays in grid
- [ ] Data saves to database via `admin_upsert_rota_assignment` RPC
- [ ] Page refresh: assignment persists

**5. Edit Draft Assignment**
- [ ] Click cell with existing draft shift
- [ ] Shift picker opens with current shift highlighted
- [ ] Select different shift
- [ ] Cell updates with new shift
- [ ] History records the change

**6. View Draft Comments**
- [ ] Click on draft cell
- [ ] Details modal opens
- [ ] Comments load correctly
- [ ] Can add/delete comments same as published

**7. Save Multiple Drafts**
- [ ] Assign shifts to multiple cells
- [ ] Navigate away and back
- [ ] All assignments persist
- [ ] No data loss occurs

---

### REQUEST MANAGEMENT WORKFLOW ⚠️

#### Pre-Requisite
- [ ] Navigate to requests.html
- [ ] Select date range or specific week

#### Test Cases

**1. View Request Interface**
- [ ] Page loads without errors
- [ ] Calendar/date picker displays
- [ ] Request grid shows properly
- [ ] User's own requests visible

**2. Submit Request**
- [ ] Click on empty request cell for a date
- [ ] Request type selector appears
- [ ] Select request type (OFF, SPECIFIC SHIFT, etc.)
- [ ] Submit button available
- [ ] Expected: `set_request_cell` RPC called with:
  ```json
  {
    "p_token": "session_token",
    "p_date": "2025-02-15",
    "p_value": "OFF",
    "p_important_rank": 5
  }
  ```

**3. Clear Request**
- [ ] Click "Clear" on existing request cell
- [ ] Cell clears
- [ ] Data removed from database
- [ ] Expected: `clear_request_cell` RPC called

**4. View Week Comments**
- [ ] For a specific week, click "View Comments"
- [ ] Modal opens showing week comments
- [ ] Comments from all users visible (if permissions allow)
- [ ] Comment author and timestamp display
- [ ] Expected: `get_week_comments` RPC called with:
  ```json
  {
    "p_week_id": "week_uuid",
    "p_token": "session_token"
  }
  ```

**5. Save Week Comment** ⚠️ **DATABASE FUNCTION NEEDS REVIEW**
- [ ] Type comment for week
- [ ] Click "Save Comment"
- [ ] Expected: `upsert_week_comment` RPC called with:
  ```json
  {
    "p_token": "session_token",
    "p_week_id": "week_uuid",
    "p_comment": "comment_text"
  }
  ```
- **Note:** This function may return errors due to database-level column ambiguity
- **Status:** RPC parameter fix applied, but PostgreSQL function needs review

**6. View Request Locks**
- [ ] Admin can set request cell locks
- [ ] Staff cannot edit locked cells
- [ ] Lock shows reason

---

### ADMIN FEATURES WORKFLOW ✅

#### User Management
- [ ] Create new user
- [ ] Edit user details (name, role)
- [ ] Set/reset user PIN
- [ ] Activate/deactivate user
- [ ] Verify `admin_upsert_user` RPC called correctly

#### Period Management
- [ ] Create 5-week period
- [ ] Set period dates correctly
- [ ] Open/close weeks
- [ ] Publish period
- [ ] Unpublish period
- [ ] All changes reflected immediately

#### Shift Management
- [ ] Add new shift to catalogue
- [ ] Edit shift properties (code, label, times, colors)
- [ ] Delete shift
- [ ] Verify `admin_upsert_shift` RPC

#### Staffing Requirements
- [ ] Set daily staffing levels
- [ ] Set by shift type (day/night, SN/NA)
- [ ] Edit requirements
- [ ] Verify `admin_upsert_staffing_requirement` RPC

#### Notices & Announcements
- [ ] Create notice
- [ ] Set target audience (all, specific roles)
- [ ] Publish notice
- [ ] Users receive notices
- [ ] Users acknowledge notices

#### Audit Trail
- [ ] Access audit logs
- [ ] Filter by user/action/resource type
- [ ] View all historical changes
- [ ] Verify `get_unified_audit_trail` RPC returns data

#### Impersonation (View As)
- [ ] Click "View As" button
- [ ] Select staff member
- [ ] View as that user
- [ ] See their version of rota/requests
- [ ] All operations logged with impersonator ID

---

### SECURITY & AUTHENTICATION ✅

#### Login Flow
- [ ] Open application (index.html)
- [ ] Username field available
- [ ] PIN field available
- [ ] Submit login
- [ ] Expected: `verify_login` RPC called with:
  ```json
  {
    "p_username": "username",
    "p_pin": "pin_hash",
    "p_ip_hash": "hashed_ip",
    "p_user_agent_hash": "hashed_user_agent"
  }
  ```
- [ ] Token returned and stored in sessionStorage
- [ ] Redirected to rota.html
- [ ] Session validated on page load

#### Session Validation
- [ ] Open developer console
- [ ] Check sessionStorage: `calpe_ward_token` exists
- [ ] Refresh page
- [ ] Session persists
- [ ] User remains logged in
- [ ] Expected: `validate_session` RPC called on load

#### Token Expiration
- [ ] Wait for token to expire (or manually clear sessionStorage)
- [ ] Perform action on page
- [ ] Redirected to login with expiration message
- [ ] Cannot access protected data

#### Permissions Check
- [ ] Non-admin user: Admin button hidden
- [ ] Non-admin user: Cannot access admin.html directly
- [ ] Admin user: Admin button visible
- [ ] Admin user: Can access admin.html
- [ ] Expected: `require_session_permissions` RPC called

#### RPC-Only Access Verification
- [ ] Open browser DevTools → Network tab
- [ ] Perform any operation (load shift, save comment, etc.)
- [ ] Check Network tab:
  - [ ] No direct Supabase `.from()` queries visible
  - [ ] All operations go through RPC function calls
  - [ ] Each RPC call includes token parameter
- [ ] Expected: All data access via SECURITY DEFINER RPC functions

---

### DATA INTEGRITY TESTS ✅

#### Comment System
- [ ] Add comment to shift
- [ ] Refresh page
- [ ] Comment persists
- [ ] Comment text unchanged
- [ ] Author correctly recorded
- [ ] Timestamp correct

#### Assignment History
- [ ] Change shift assignment
- [ ] View history
- [ ] Previous shift shows in history
- [ ] Timestamp of change recorded
- [ ] "Changed by" field shows operator name

#### Request Tracking
- [ ] Submit request
- [ ] Check audit logs
- [ ] Request logged with request type
- [ ] User ID recorded
- [ ] Timestamp recorded

#### Staffing Calculations
- [ ] Update staffing requirements
- [ ] Calculate vs. actual staffing
- [ ] Verify totals match
- [ ] Expected: `rpc_get_staffing_totals` returns accurate data

---

### PERFORMANCE TESTS

#### Page Load Time
- [ ] Rota.html loads in < 3 seconds
- [ ] Requests.html loads in < 3 seconds
- [ ] Admin.html loads in < 3 seconds
- [ ] No console errors or warnings

#### Data Load Time
- [ ] Loading 5-week period: < 2 seconds
- [ ] 50+ staff members: < 2 seconds
- [ ] 200+ requests: < 3 seconds

#### UI Responsiveness
- [ ] Grid scrolling smooth (60 fps)
- [ ] Modal opens instantly
- [ ] Buttons respond immediately
- [ ] No lag when typing comments

#### Concurrent Users
- [ ] Multiple admins editing simultaneously
- [ ] No conflicts or data corruption
- [ ] Audit log shows all changes
- [ ] Real-time updates work (if implemented)

---

### ERROR HANDLING TESTS

#### Network Errors
- [ ] Disconnect internet mid-operation
- [ ] Expected: Error message displays
- [ ] Expected: Retry option available
- [ ] Expected: No data corruption

#### Invalid Token
- [ ] Manually corrupt sessionStorage token
- [ ] Try to perform operation
- [ ] Expected: Redirect to login
- [ ] Expected: Error message shown

#### Permission Denied
- [ ] Non-admin tries to access admin function
- [ ] Expected: Permission denied error (402 status or similar)
- [ ] Expected: User-friendly error message

#### RPC Function Errors
- [ ] Check browser console for RPC errors
- [ ] All errors should have descriptive messages
- [ ] No generic "error" responses
- [ ] Errors logged in audit trail

---

### BROWSER COMPATIBILITY

- [ ] Chrome/Chromium (latest)
- [ ] Firefox (latest)
- [ ] Safari (latest)
- [ ] Edge (latest)
- [ ] Mobile browsers (iOS Safari, Chrome Mobile)

---

### MOBILE RESPONSIVENESS

- [ ] Layout adapts to small screens
- [ ] Touch interactions work
- [ ] Modal sizing appropriate
- [ ] No horizontal scroll required
- [ ] Buttons easily tappable (48px+ minimum)

---

## 📋 TEST EXECUTION TEMPLATE

### Test Session: _______________
**Date:** ________________  
**Tester:** ________________  
**Environment:** ________________  

| Test Case | Steps | Expected Result | Actual Result | Pass/Fail | Notes |
|-----------|-------|-----------------|---------------|-----------|-------|
| | | | | | |
| | | | | | |
| | | | | | |

---

## 🚨 Known Issues & Limitations

### 1. Week Comment Upsert Function ⚠️
**Issue:** Database function `upsert_week_comment` may fail due to column ambiguity  
**Status:** RPC parameters corrected, but PostgreSQL function needs review  
**Workaround:** Retry operation if it fails  
**Fix Timeline:** Requires database function code review and correction

### 2. No Real-Time Updates (Realtime Not Configured)
**Issue:** Multiple users won't see each other's changes in real-time  
**Status:** By design (would require Realtime subscription setup)  
**Workaround:** Refresh page to see latest data  
**Impact:** Not critical for scheduling application

---

## ✅ Sign-Off Template

```
TEST EXECUTION COMPLETE

Total Tests: _____ / _____ Passed
Success Rate: _____%

Critical Issues: ______
Major Issues: ______
Minor Issues: ______

APPROVAL:
[ ] All critical tests passed
[ ] All major tests passed
[ ] Ready for production deployment
[ ] Requires additional testing

Tester Name: ____________________
Date: ____________________
Signature: ____________________
```

---

**This checklist ensures comprehensive validation of all Calpe Ward features post-migration.**

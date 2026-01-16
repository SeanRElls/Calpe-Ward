# DEPLOYMENT CHECKLIST: Token-Only RPC Migration

**Date**: ________________  
**Deployed By**: ________________  
**Start Time**: ________________  

---

## ✅ PRE-DEPLOYMENT (Before Running Anything)

### Document Review (15 minutes)
- [ ] Read TOKEN_ONLY_MIGRATION_SUMMARY.md (executive summary)
- [ ] Read REQUIRE_SESSION_PERMISSIONS_SPEC.md (verify function exists)
- [ ] Read MIGRATION_REVIEW_CHECKLIST.md (understand pre-flight requirements)
- [ ] Review ARCHITECTURE_DIAGRAMS.md (understand security flow)

### Database Pre-Flight Checks (10 minutes)
Run these in Supabase SQL Editor (copy-paste from MIGRATION_REVIEW_CHECKLIST.md section 4.1):

```
Query 1: Check require_session_permissions() exists
SELECT COUNT(*) as count FROM pg_proc 
WHERE proname = 'require_session_permissions'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
```
- [ ] Result: **1** (if 0, create function from REQUIRE_SESSION_PERMISSIONS_SPEC.md)
- [ ] Function is SECURITY DEFINER: **YES** / **NO**
- [ ] Note any issues: _________________________________________________

```
Query 2: Check permission keys exist
SELECT COUNT(*) as count FROM permission_items 
WHERE permission_key IN (
  'manage_shifts', 'notices.view_admin', 'notices.view_ack_lists',
  'notices.create', 'notices.edit', 'notices.delete', 'notices.toggle_active',
  'periods.set_active', 'periods.set_close_time', 'periods.toggle_hidden',
  'requests.edit_all', 'requests.lock_cells', 'weeks.set_open_flags',
  'users.create', 'users.edit', 'users.toggle_active', 'users.set_pin', 'users.reorder'
);
```
- [ ] Result: **18** (if less, create missing keys—see MIGRATION_REVIEW_CHECKLIST.md)
- [ ] Missing keys: _________________________________________________

```
Query 3: Check sessions table structure
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'sessions'
AND column_name IN ('token', 'user_id', 'expires_at', 'revoked_at')
ORDER BY ordinal_position;
```
- [ ] Has `token` (uuid): **YES** / **NO**
- [ ] Has `user_id` (uuid): **YES** / **NO**
- [ ] Has `expires_at` (timestamp): **YES** / **NO**
- [ ] Has `revoked_at` (timestamp): **YES** / **NO**

### Code Review (10 minutes)
- [ ] Verify `sql/migrate_to_token_only_rpcs.sql` exists (1422 lines)
- [ ] Verify updated frontend files exist:
  - [ ] `js/app.js` (26 RPC calls updated)
  - [ ] `js/admin.js` (7 RPC calls updated)
  - [ ] `js/swap-functions.js` (3 RPC calls updated)
  - [ ] `rota.html` (6 RPC calls updated)
  - [ ] `index.html` (12+ RPC calls updated)

### Team Communication (5 minutes)
- [ ] Notify team: Migration starting in X minutes
- [ ] Get approval from: _________________
- [ ] Post link to support docs in team chat
- [ ] Request no new deployments during migration window

### Final Safety Checks (5 minutes)
- [ ] Database backup: **VERIFIED** (Supabase auto-backups enabled)
- [ ] Frontend can be rolled back: **YES** / **NO** (git history preserved)
- [ ] Rollback procedures understood: **YES** / **NO**
- [ ] All pre-flight checks passed: **YES** / **NO** → **STOP** if NO

---

## 🚀 DEPLOYMENT PHASE 1: SQL MIGRATION (5 minutes)

**Start Time**: ________________

### Step 1.1: Prepare SQL Script
- [ ] Open `sql/migrate_to_token_only_rpcs.sql` in text editor
- [ ] Verify contains `BEGIN;` at start and `COMMIT;` at end
- [ ] Copy entire contents to clipboard (Ctrl+A, Ctrl+C)
- [ ] Note first line: _________________________________________________

### Step 1.2: Execute in Supabase
- [ ] Log into Supabase (supabase.com)
- [ ] Select correct project
- [ ] Go to SQL Editor
- [ ] Click "+ New Query"
- [ ] Paste entire script (Ctrl+V)
- [ ] Click **"Run"**

### Step 1.3: Monitor Execution
- [ ] Watch for "Success" message
- [ ] Check status bar: **Running** → **Complete**
- [ ] Execution time: ________________ (expect ~30 seconds)
- [ ] Any error messages? **NO** (if YES, screenshot and investigate)

### Step 1.4: Verify Migration Success
Run these queries in same SQL editor (from MIGRATION_REVIEW_CHECKLIST.md section 4.2):

```
Post-Migration Query 1: Verify new functions exist
SELECT COUNT(*) as staff_func_count FROM pg_proc
WHERE proname IN (
  'get_unread_notices', 'get_all_notices', 'ack_notice', 'set_request_cell'
)
AND pg_get_function_identity_arguments(oid) ~ '^p_token'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
```
- [ ] Result: **4+** functions with token-only signature
- [ ] If less, query failed—investigate

```
Post-Migration Query 2: Verify old overloads are gone
SELECT COUNT(*) as old_overload_count FROM pg_proc
WHERE proname IN ('ack_notice', 'get_all_notices', 'set_request_cell')
AND pg_get_function_identity_arguments(oid) ~ 'p_user_id.*p_pin'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
```
- [ ] Result: **0** (old overloads deleted)
- [ ] If > 0, old overloads still exist—investigate

```
Post-Migration Query 3: Check for errors
SELECT COUNT(*) FROM pg_proc
WHERE proname ~ 'admin_|get_|ack_|set_request_|clear_request_'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
```
- [ ] Result: **40+** functions present
- [ ] Sample function exists: ________________

- [ ] ✅ **SQL MIGRATION COMPLETE** (Time: ______________)

---

## 🚀 DEPLOYMENT PHASE 2: FRONTEND DEPLOYMENT (5-15 minutes)

**Start Time**: ________________

### Step 2.1: Code Commit
- [ ] Open terminal in project directory
- [ ] Verify changes: `git status`
  - [ ] Shows modified: js/app.js, js/admin.js, js/swap-functions.js, rota.html, index.html
- [ ] Stage changes: `git add js/app.js js/admin.js js/swap-functions.js rota.html index.html`
- [ ] Commit: `git commit -m "chore: migrate RPC calls to token-only auth"`
- [ ] Verify commit message: _________________________________________________

### Step 2.2: Push to Repository
- [ ] Run: `git push origin [main/master/develop]`
- [ ] Wait for push to complete
- [ ] Verify no merge conflicts: **NONE** / **FOUND**
  - [ ] If conflicts found, resolve before proceeding
- [ ] GitHub/GitLab shows commit: **YES** / **NO**

### Step 2.3: Deploy to Production
**Choose your deployment method**:

**Option A: Automated CI/CD**
- [ ] GitHub Actions / GitLab CI triggered automatically
- [ ] Watch deployment pipeline
- [ ] Wait for `✅ Deploy to production` status
- [ ] Deployment time: ________________

**Option B: Manual Deployment**
- [ ] Deploy web app (your method): _________________________________________________
- [ ] Verify app started successfully
- [ ] Check health endpoint: _________________________________________________
- [ ] Deployment time: ________________

### Step 2.4: Cache Invalidation
- [ ] Clear browser cache (Cmd/Ctrl + Shift + Delete)
  - [ ] Empty cache
  - [ ] Clear cookies (optional but recommended)
  - [ ] Restart browser
- [ ] Test in incognito/private window (cache-free)
- [ ] OR bump asset versions in index.html:
  ```html
  <script src="js/app.js?v=2.0.0"></script>  ← Add ?v=version
  ```
  - [ ] Updated version numbers in index.html
  - [ ] Re-deployed with new versions

- [ ] ✅ **FRONTEND DEPLOYMENT COMPLETE** (Time: ______________)

---

## 🧪 SMOKE TESTING PHASE (15-20 minutes)

**Start Time**: ________________

### Test 1: Staff User - Fetch Notices
```javascript
// Open browser console (F12)
console.log('Token:', window.currentToken);  
// Expected: UUID like a1b2c3d4-e5f6...

console.log('User:', window.currentUser.is_admin);
// Expected: false (if staff) or true (if admin)

// Open browser console and run:
const { data, error } = await window.supabaseClient.rpc(
  'get_unread_notices',
  { p_token: window.currentToken }
);
console.log('Data:', data ? data.length + ' notices' : 'null');
console.log('Error:', error ? error.message : 'null');
```
- [ ] **Result**: Data returned, no error
- [ ] Expected: Array of notices or empty array
- [ ] If error: ___________________________

### Test 2: Staff User - Acknowledge Notice
- [ ] Find a notice ID from Test 1
- [ ] Run in console:
```javascript
const { error } = await window.supabaseClient.rpc('ack_notice', {
  p_token: window.currentToken,
  p_notice_id: 'NOTICE_ID_HERE',
  p_version: 1
});
console.log('Error:', error ? error.message : 'Success!');
```
- [ ] **Result**: No error
- [ ] Notice disappears from unread: **YES** / **NO**
- [ ] If error: ___________________________

### Test 3: Staff User - Set Request Cell
```javascript
const { data, error } = await window.supabaseClient.rpc('set_request_cell', {
  p_token: window.currentToken,
  p_date: '2026-02-01',
  p_value: 'LD',
  p_important_rank: 1
});
console.log('Data:', data);
console.log('Error:', error ? error.message : 'null');
```
- [ ] **Result**: Success (data shows success or no error)
- [ ] If error: ___________________________

### Test 4: Admin User - Approve Swap
- [ ] Log in as admin user
- [ ] Get a pending swap request ID
- [ ] Run in console:
```javascript
const { data, error } = await window.supabaseClient.rpc(
  'admin_approve_swap_request',
  {
    p_token: window.currentToken,
    p_swap_request_id: 'SWAP_ID_HERE'
  }
);
console.log('Data:', data);
console.log('Error:', error ? error.message : 'null');
```
- [ ] **Result**: Success or specific error (not permission_denied)
- [ ] If error: ___________________________

### Test 5: Non-Admin Without Permission - Should Fail
- [ ] Log in as non-admin user
- [ ] Verify user does NOT have 'manage_shifts' permission
- [ ] Run:
```javascript
const { error } = await window.supabaseClient.rpc(
  'admin_approve_swap_request',
  {
    p_token: window.currentToken,
    p_swap_request_id: 'any-uuid'
  }
);
console.log('Error:', error ? error.message : 'null');
```
- [ ] **Result**: `permission_denied`
- [ ] If different: ___________________________

### Test 6: Invalid Token - Should Fail
```javascript
const { error } = await window.supabaseClient.rpc(
  'get_unread_notices',
  { p_token: '00000000-0000-0000-0000-000000000000' }
);
console.log('Error:', error ? error.message : 'null');
```
- [ ] **Result**: `invalid_session`
- [ ] If different: ___________________________

### Test 7: Application Features
- [ ] Log in page works: **YES** / **NO**
- [ ] Dashboard loads: **YES** / **NO**
- [ ] Rota view loads: **YES** / **NO**
- [ ] Admin panel loads (if admin): **YES** / **NO**
- [ ] No JavaScript errors in console: **NONE** / **FOUND**
  - [ ] If errors, describe: _________________________________________________

- [ ] ✅ **SMOKE TESTING COMPLETE** (Time: ______________)

---

## 📊 MONITORING PHASE (24 hours)

**Start Time**: ________________  
**Monitor Until**: ________________

### Continuous Monitoring
- [ ] Set up alerts for RPC errors in monitoring dashboard
- [ ] Watch Supabase logs every hour for first 4 hours
- [ ] Check application error tracking service
- [ ] Verify no unexpected permission_denied messages

### Hour 1 (Immediate)
- [ ] Check error logs: **NONE** / **FOUND**
- [ ] User-reported issues: **NONE** / **FOUND**
- [ ] RPC response times normal: **YES** / **NO**
- [ ] Sample log query results: _________________________________________________

### Hour 4
- [ ] Total errors since deployment: ________________
- [ ] Critical issues: **NONE** / **FOUND**
- [ ] Team feedback: _________________________________________________

### Hour 24
- [ ] Total errors last 24h: ________________
- [ ] Error rate: ________________ %
- [ ] All systems operating normally: **YES** / **NO**
- [ ] Any rollback needed: **NO** / **YES** (if yes, start ROLLBACK below)

- [ ] ✅ **MONITORING COMPLETE** (Time: ______________)

---

## ✅ POST-DEPLOYMENT (If Successful)

- [ ] Mark this deployment as **COMPLETE AND SUCCESSFUL**
- [ ] Update system status page
- [ ] Notify team: "Token-only RPC migration deployed successfully"
- [ ] Archive this checklist and monitoring notes
- [ ] Schedule follow-up review for next week
- [ ] Document any issues encountered: _________________________________________________

**Final Status**: ✅ **MIGRATION SUCCESSFUL**

**Approval Signature**: ________________  
**Date/Time**: ________________

---

## ⚠️ ROLLBACK PROCEDURE (If Issues Occur)

### STOP! Before Rolling Back:
- [ ] Is issue actually migration-related? **YES** / **NO**
- [ ] Have you reviewed TROUBLESHOOTING in MIGRATION_REVIEW_CHECKLIST.md? **YES** / **NO**
- [ ] Is issue a known limitation (listed below)? **YES** / **NO**

### Known Limitations (NOT rollback-worthy):
- Legacy PIN functions not migrated (get_week_comments, change_user_pin, etc.)
- These will be handled in Phase 2
- Not blocking core functionality

### Rollback Steps (If Truly Necessary)

**Step 1: Frontend Revert (5 minutes)**
```bash
git revert HEAD  # Revert last commit
# OR
git checkout main~1 -- js/app.js js/admin.js js/swap-functions.js rota.html index.html
git commit -m "revert: RPC migration"
git push origin main
```
- [ ] Completed
- [ ] Redeployed
- [ ] Cache cleared

**Step 2: Database Restore (15-60 minutes, REQUIRES DOWNTIME)**
- [ ] Contact Supabase support: support@supabase.com
- [ ] Request restore from backup (pre-migration)
- [ ] Provide backup timestamp: _________________________________________________
- [ ] Wait for restoration
- [ ] Verify old functions are back

**Step 3: Re-enable Old Frontend**
- [ ] Verify database is back to pre-migration state
- [ ] Redeploy frontend (old version)
- [ ] Clear caches
- [ ] Test old functions work again

- [ ] ⚠️ **ROLLBACK COMPLETE** (Time: ______________)

---

## 📝 NOTES & ISSUES LOG

### Issues Encountered
| Time | Issue | Resolution | Status |
|------|-------|-----------|--------|
|      |       |           |        |
|      |       |           |        |
|      |       |           |        |

### Decisions Made
| Decision | Reason | Time |
|----------|--------|------|
|          |        |      |
|          |        |      |

### Follow-Up Tasks
- [ ] _________________________________________________
- [ ] _________________________________________________
- [ ] _________________________________________________

---

## 🔗 USEFUL LINKS & CONTACTS

**Documentation**:
- [TOKEN_ONLY_MIGRATION_SUMMARY.md](TOKEN_ONLY_MIGRATION_SUMMARY.md)
- [MIGRATION_REVIEW_CHECKLIST.md](MIGRATION_REVIEW_CHECKLIST.md)
- [REQUIRE_SESSION_PERMISSIONS_SPEC.md](REQUIRE_SESSION_PERMISSIONS_SPEC.md)
- [ARCHITECTURE_DIAGRAMS.md](ARCHITECTURE_DIAGRAMS.md)

**Database**:
- Supabase Project: [URL]
- SQL Editor: [URL]

**Code Repository**:
- GitHub/GitLab: [URL]
- Main branch: [branch-name]

**Team Contacts**:
- Project Lead: [Name] ([Email])
- DevOps: [Name] ([Email])
- Database Admin: [Name] ([Email])
- Support Escalation: [Contact]

---

**Deployment Checklist Version**: 1.0  
**Last Updated**: 2026-01-16  
**Status**: Ready for Use ✅

---

**REMEMBER**: This is a BREAKING change to RPC signatures. Ensure **ALL** frontend code is updated before deploying SQL. Deploy SQL first, then frontend immediately after (same day).

**Questions?** See [MIGRATION_REVIEW_CHECKLIST.md](MIGRATION_REVIEW_CHECKLIST.md#5-troubleshooting)

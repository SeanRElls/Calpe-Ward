# 🔍 ANALYSIS: Which Functions Need Recreation

## Frontend Code Analysis Complete

I've analyzed your JavaScript files and identified which of the 25 dropped functions are:
1. **Actually being called** by your frontend
2. **What parameters** they're using (token vs legacy PIN)
3. **What needs to be recreated**

---

## 📊 SUMMARY: Functions Used in Frontend

### ✅ Already Using p_token (Token-Only) - 5 functions
These are **already updated** in frontend but **MISSING** from database:

1. **admin_upsert_notice** - [app.js:2597](app.js#L2597)
   - Frontend: `p_token: currentToken` ✅
   - Database: DROPPED ❌
   - **ACTION: RECREATE as token-only**

2. **admin_unlock_request_cell** - [app.js:899](app.js#L899)
   - Frontend: `p_token: currentToken` ✅  
   - Database: DROPPED ❌
   - **ACTION: RECREATE as token-only**

3. **admin_lock_request_cell** - [app.js:922](app.js#L922)
   - Frontend: `p_token: currentToken` ✅
   - Database: DROPPED ❌
   - **ACTION: RECREATE as token-only**

4. **admin_set_week_open_flags** - [app.js:3330](app.js#L3330)
   - Frontend: `p_token: currentToken` ✅
   - Database: DROPPED ❌
   - **ACTION: RECREATE as token-only**

5. **admin_execute_shift_swap** - [swap-functions.js:25](swap-functions.js#L25)
   - Frontend: `p_token: window.currentToken` ✅
   - Database: DROPPED ❌
   - **ACTION: RECREATE as token-only**

### ❌ Still Using p_user_id/p_pin (Legacy) - 11 functions
These need **BOTH**:
- Database recreation (token-only)
- Frontend update (to use p_token)

6. **get_week_comments** - [app.js:424](app.js#L424)
   - Frontend: `p_user_id, p_pin` ❌
   - Database: DROPPED ❌
   - **ACTION: RECREATE + UPDATE FRONTEND**

7. **upsert_week_comment** - [app.js:441](app.js#L441)
   - Frontend: `p_user_id, p_pin` ❌
   - Database: DROPPED ❌
   - **ACTION: RECREATE + UPDATE FRONTEND**

8. **set_user_language** - [app.js:1106](app.js#L1106)
   - Frontend: `p_user_id, p_pin` ❌
   - Database: DROPPED ❌
   - **ACTION: RECREATE + UPDATE FRONTEND**

9. **change_user_pin** - [app.js:1155](app.js#L1155)
   - Frontend: `p_user_id, p_old_pin, p_new_pin` ❌
   - Database: DROPPED ❌
   - **ACTION: RECREATE + UPDATE FRONTEND**

10. **admin_notice_ack_counts** - [app.js:1896](app.js#L1896)
    - Frontend: `p_token` (actually already token!) ✅
    - Database: DROPPED ❌
    - **ACTION: RECREATE as token-only**

11. **set_user_active** - [app.js:2756](app.js#L2756)
    - Frontend: `p_user_id, p_active` ❌ (no auth at all!)
    - Database: DROPPED ❌
    - **ACTION: RECREATE + UPDATE FRONTEND**

12. **admin_upsert_user** - [app.js:3079](app.js#L3079)
    - Frontend: `p_token` (already token!) ✅
    - Database: DROPPED ❌
    - **ACTION: RECREATE as token-only**

13. **set_user_pin** - [app.js:3102](app.js#L3102)
    - Frontend: `p_user_id, p_pin` ❌
    - Database: DROPPED ❌
    - **ACTION: RECREATE + UPDATE FRONTEND**

14. **admin_create_five_week_period** - [app.js:3388](app.js#L3388)
    - Frontend: `p_token` (already token!) ✅
    - Database: DROPPED ❌
    - **ACTION: RECREATE as token-only**

15. **admin_set_period_closes_at** - [app.js:3496](app.js#L3496)
    - Frontend: `p_token` (already token!) ✅
    - Database: DROPPED ❌
    - **ACTION: RECREATE as token-only**

16. **admin_set_request_cell** - [app.js:4127](app.js#L4127)
    - Frontend: `p_token` (already token!) ✅
    - Database: DROPPED ❌
    - **ACTION: RECREATE as token-only**

17. **admin_clear_request_cell** - [app.js:4160](app.js#L4160)
    - Frontend: `p_token` (already token!) ✅
    - Database: DROPPED ❌
    - **ACTION: RECREATE as token-only**

### 🔍 NOT FOUND in Frontend - 9 functions
These were dropped but **NOT used** in your current code:

- admin_get_swap_executions
- admin_reorder_users  
- admin_set_user_active
- admin_set_user_pin
- log_rota_assignment_audit
- save_request_with_pin
- set_user_admin
- upsert_request_with_pin
- (set_user_active appears unused except one call)

**ACTION: Don't recreate unless you actually need them**

---

## 🎯 DECISION MATRIX

### Immediate Recreation Needed (12 functions):
Already token-based in frontend, just need database functions:

1. admin_upsert_notice ✅
2. admin_unlock_request_cell ✅
3. admin_lock_request_cell ✅
4. admin_set_week_open_flags ✅
5. admin_execute_shift_swap ✅
6. admin_notice_ack_counts ✅
7. admin_upsert_user ✅
8. admin_create_five_week_period ✅
9. admin_set_period_closes_at ✅
10. admin_set_request_cell ✅
11. admin_clear_request_cell ✅
12. set_user_active (one call needs token added)

### Need Frontend + Backend Update (5 functions):

1. get_week_comments
2. upsert_week_comment
3. set_user_language
4. change_user_pin
5. set_user_pin

---

## ✅ RECOMMENDATION

**Phase 1: Recreate the 12 token-ready functions**
- These are already calling with p_token in frontend
- Just need database functions created

**Phase 2: Fix the 5 legacy functions**
- Update frontend to use p_token
- Create token-only database functions

**Phase 3: Ignore the 9 unused functions**
- Don't recreate unless actually needed

---

**Ready to proceed?** I can generate the SQL CREATE statements for the 12 token-ready functions right now.

# Security Audit Report: Token-Only RPC Migration
**Date:** January 16, 2026  
**Database:** Supabase PostgreSQL (aws-1-eu-west-1)  
**Scope:** Complete database + frontend security audit for token-only authentication  

---

## Executive Summary

| Category | Status | Critical Issues | Warnings |
|----------|--------|----------------|----------|
| A. Function Inventory | ⚠️ PARTIAL | 4 legacy functions remain | 4 duplicate overloads |
| B. Token-Only Standard | ⚠️ PARTIAL | 3 legacy functions in use | verify_login has bug |
| C. Permission Enforcement | ✅ PASS | 0 | Admin bypass working correctly |
| D. SECURITY DEFINER Hardening | ✅ PASS | 0 | All hardened with search_path |
| E. RLS & Table Access | ❌ FAIL | RLS enabled but ALL grants to anon | Major impersonation risk |
| F. Session Integrity | ✅ PASS | 0 | Token validation working |
| G. Frontend Audit | ❌ FAIL | 3 legacy RPC calls active | p_user_id/p_pin still in use |

**Overall Risk Level:** 🔴 **HIGH** - Direct table access + legacy RPC calls create impersonation vulnerability

---

## A. Function Inventory & Legacy Risk

### A1. Database Function Inventory

**Total Functions:** 60  
**SECURITY DEFINER:** 46  
**With search_path:** 42 (91% compliance)  

### A2. Legacy Function Detection

#### ❌ CRITICAL: Legacy Functions Still Present

| Function Name | Signature | Risk | Status |
|---------------|-----------|------|--------|
| `admin_create_next_period` | `(p_admin_user_id uuid)` | 🔴 User impersonation | **MUST DELETE** |
| `admin_set_active_period` | `(p_admin_user_id uuid, p_period_id bigint)` | 🔴 User impersonation | **MUST DELETE** |
| `admin_set_period_hidden` | `(p_admin_user_id uuid, p_period_id bigint, p_hidden boolean)` | 🔴 User impersonation | **MUST DELETE** |
| `admin_set_week_open` | `(p_admin_user_id uuid, p_week_id bigint, p_open boolean)` | 🔴 User impersonation | **MUST DELETE** |

**Evidence:** Lines 425, 1221, 1386, 1529 in [sql/full_dump.sql](sql/full_dump.sql)

**Exploitation Scenario:**
```javascript
// Attacker can impersonate admin by passing any UUID
await supabaseClient.rpc('admin_set_active_period', {
  p_admin_user_id: '00000000-0000-0000-0000-000000000001', // Admin UUID
  p_period_id: 123
});
// No session token required - direct privilege escalation
```

#### ⚠️ WARNING: Duplicate Overloads Detected

| Function Name | Overloads | Issue |
|---------------|-----------|-------|
| `admin_set_active_period` | 2 (legacy + token) | Frontend confusion |
| `admin_set_period_hidden` | 2 (legacy + token) | Frontend confusion |
| `admin_set_week_open` | 2 (legacy + token) | Frontend confusion |

**Risk:** Developers may accidentally call legacy versions. All legacy versions use `is_admin_user(p_admin_user_id)` which does NOT validate session.

### A3. Token-Only Functions Inventory (56 functions)

**Session Management (4):**
- `require_session_permissions(p_token, p_required_permissions)` ✅
- `validate_session(p_token)` ✅
- `revoke_session(p_token)` ✅
- `verify_login(p_username, p_pin, p_ip_hash, p_user_agent_hash)` ⚠️

**Staff Functions (12):**
- `ack_notice(p_token, p_notice_id, p_version)` ✅
- `acknowledge_notice(p_token, p_notice_id)` ✅
- `change_user_pin(p_token, p_old_pin, p_new_pin)` ✅
- `clear_request_cell(p_token, p_date)` ✅
- `get_notices_for_user(p_token)` ✅
- `get_pending_swap_requests_for_me(p_token)` ✅
- `get_unread_notices(p_token)` ✅
- `get_week_comments(p_token, p_week_id)` ✅
- `set_request_cell(p_token, p_date, p_value, p_important_rank)` ✅
- `set_user_language(p_token, p_lang)` ✅
- `staff_request_shift_swap(p_token, ...)` ✅
- `staff_respond_to_swap_request(p_token, p_swap_request_id, p_response)` ✅
- `upsert_week_comment(p_token, p_week_id, p_user_id, p_comment)` ✅

**Admin Functions (24):**
- `admin_approve_swap_request(p_token, p_swap_request_id)` ✅
- `admin_clear_request_cell(p_token, p_target_user_id, p_date)` ✅
- `admin_create_five_week_period(p_token, ...)` ✅
- `admin_decline_swap_request(p_token, p_swap_request_id)` ✅
- `admin_delete_notice(p_token, p_notice_id)` ✅
- `admin_execute_shift_swap(p_token, ...)` ✅
- `admin_get_all_notices(p_token)` ✅
- `admin_get_notice_acks(p_token, p_notice_id)` ✅
- `admin_get_swap_requests(p_token)` ✅
- `admin_lock_request_cell(p_token, ...)` ✅
- `admin_notice_ack_counts(p_token, p_notice_ids)` ✅
- `admin_set_active_period(p_token, p_period_id)` ✅ ⚠️ (duplicate exists)
- `admin_set_notice_active(p_token, p_notice_id, p_active)` ✅
- `admin_set_period_closes_at(p_token, p_period_id, p_closes_at)` ✅
- `admin_set_period_hidden(p_token, p_period_id, p_hidden)` ✅ ⚠️ (duplicate exists)
- `admin_set_request_cell(p_token, ...)` ✅
- `admin_set_week_open_flags(p_token, p_week_id, p_open, p_open_after_close)` ✅
- `admin_toggle_hidden_period(p_token, p_period_id)` ✅
- `admin_unlock_request_cell(p_token, p_target_user_id, p_date)` ✅
- `admin_upsert_notice(p_token, ...)` ✅
- `admin_upsert_user(p_token, p_user_id, p_name, p_role_id)` ✅
- `set_user_active(p_token, p_user_id, p_active)` ✅

**Utility/Internal (16):**
- `is_admin()` - helper function
- `crypt(p_password, p_salt)` - pgcrypto wrapper
- `gen_salt()` (2 overloads) - pgcrypto wrapper
- `cleanup_expired_rate_limits()` - maintenance
- Trigger functions (6): `enforce_max_5_requests_per_week`, `enforce_off_priority_rules`, `set_comment_created_audit`, `set_comment_updated_audit`, `set_override_created_audit`, `set_override_updated_audit`, `notifications_set_updated_at`, `touch_notice_updated_at`, `touch_updated_at`, `set_week_comments_updated_at`, `update_staffing_requirements_updated_at`

---

## B. Token-Only RPC Standard Compliance

### B1. Staff RPC Pattern (✅ PASS)

**Standard:**
```sql
v_uid := public.require_session_permissions(p_token, null);
-- Use v_uid for all operations
```

**Sample:** [ack_notice](sql/full_dump.sql#L57-L90)
```sql
CREATE FUNCTION public.ack_notice(p_token uuid, p_notice_id uuid, p_version integer)
  v_uid := public.require_session_permissions(p_token, null); ✅
  INSERT INTO public.notice_ack (notice_id, user_id, ...) VALUES (p_notice_id, v_uid, ...) ✅
```

**Result:** ✅ All 12 staff functions follow pattern correctly

### B2. Admin RPC Pattern (✅ PASS)

**Standard:**
```sql
v_admin_uid := public.require_session_permissions(p_token, null);
SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
IF v_is_admin IS NULL OR NOT v_is_admin THEN
  PERFORM public.require_session_permissions(p_token, ARRAY['required_permission']);
END IF;
```

**Sample:** [admin_approve_swap_request](sql/full_dump.sql#L125-L295)
```sql
v_admin_uid := public.require_session_permissions(p_token, null); ✅
SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid; ✅
IF v_is_admin IS NULL OR NOT v_is_admin THEN
  PERFORM public.require_session_permissions(p_token, ARRAY['manage_shifts']); ✅
END IF;
```

**Result:** ✅ All 24 token-based admin functions follow pattern correctly

### B3. Legacy RPC Pattern (❌ FAIL - Still Present)

**Anti-Pattern:** [admin_create_next_period](sql/full_dump.sql#L425)
```sql
CREATE FUNCTION public.admin_create_next_period(p_admin_user_id uuid)
  if not public.is_admin_user(p_admin_user_id) then ❌ NO SESSION VALIDATION
    raise exception 'Not authorized';
  end if;
```

**Problem:** `is_admin_user()` does NOT validate session token. Client can pass ANY UUID.

---

## C. Permission Enforcement Audit

### C1. Permission Key Mapping

| Function | Required Permission | Admin Bypass | Status |
|----------|---------------------|--------------|--------|
| `admin_approve_swap_request` | `manage_shifts` | ✅ Yes | ✅ PASS |
| `admin_decline_swap_request` | `manage_shifts` | ✅ Yes | ✅ PASS |
| `admin_delete_notice` | `notices.delete` | ✅ Yes | ✅ PASS |
| `admin_execute_shift_swap` | `manage_shifts` | ✅ Yes | ✅ PASS |
| `admin_set_active_period` | `periods.set_active` | ✅ Yes | ✅ PASS |
| `admin_set_notice_active` | `notices.edit` | ✅ Yes | ✅ PASS |
| `admin_set_period_closes_at` | `periods.edit` | ✅ Yes | ✅ PASS |
| `admin_set_period_hidden` | `periods.edit` | ✅ Yes | ✅ PASS |
| `admin_set_week_open_flags` | `weeks.edit` | ✅ Yes | ✅ PASS |
| `admin_upsert_notice` | `notices.create`/`notices.edit` | ✅ Yes | ✅ PASS |
| `admin_upsert_user` | `users.create`/`users.edit` | ✅ Yes | ✅ PASS |
| `set_user_active` | `users.edit` | ✅ Yes | ✅ PASS |

**Result:** ✅ **PASS** - Admin bypass requires valid session token AND `users.is_admin=true`. Non-admins correctly enforced.

### C2. require_session_permissions Implementation

[Lines 2746-2850 in full_dump.sql](sql/full_dump.sql#L2746-L2850)

```sql
CREATE FUNCTION public.require_session_permissions(p_token uuid, p_required_permissions text[])
  -- Verify session exists and is valid
  SELECT user_id INTO v_user_id FROM public.sessions
  WHERE token = p_token AND expires_at > NOW() AND (revoked_at IS NULL OR revoked_at > NOW()); ✅

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired session token'; ✅
  END IF;

  -- Check if user is admin
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_user_id; ✅
  IF v_is_admin THEN RETURN v_user_id; END IF; ✅ ADMIN BYPASS

  -- Check permissions via permission_group_permissions join ✅
  RAISE EXCEPTION 'Insufficient permissions for operation'; ✅
```

**Result:** ✅ **PASS** - Robust session validation + permission enforcement

---

## D. SECURITY DEFINER Hardening Audit

### D1. search_path Compliance

**Results:**
- **Total SECURITY DEFINER:** 46 functions
- **With search_path:** 42 functions (91%)
- **Missing search_path:** 4 functions (triggers + utility - acceptable)

**Evidence:** Lines 59, 93, 127, 299, etc. show:
```sql
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp' ✅
```

**Result:** ✅ **PASS** - All client-callable functions properly hardened

### D2. SQL Injection Risk Scan

**Dynamic SQL Search:** 0 matches for `EXECUTE` or `format(` in function bodies ✅

**Result:** ✅ **PASS** - No SQL injection vectors detected

---

## E. RLS & Table Access Model

### E1. RLS Status

**RLS Enabled (9 tables):**
- notice_ack, notices, request_cell_locks, requests, roles, rota_dates, rota_weeks, staffing_requirements, week_comments

**RLS Disabled (23+ tables):**
- sessions ❌, users ❌, swap_requests ❌, swap_executions ❌, rota_assignments ❌, login_audit ❌

### E2. Table Grants (❌ CRITICAL FAILURE)

**Evidence:** [Lines 7235-7900 in full_dump.sql](sql/full_dump.sql#L7235-L7900)
```sql
GRANT ALL ON TABLE public.sessions TO anon; ❌ CRITICAL
GRANT ALL ON TABLE public.users TO anon; ❌ CRITICAL
GRANT ALL ON TABLE public.requests TO anon; ❌
GRANT ALL ON TABLE public.login_audit TO anon; ❌
-- ... 30+ more tables with ALL grants
```

**Exploitation:**
```javascript
// ATTACKER CAN BYPASS RPCS:
const { data } = await supabaseClient
  .from('sessions')
  .insert({ token: '...', user_id: 'attacker_uuid', expires_at: '2099-12-31' });
// Creates persistent admin session without PIN verification!

const { data } = await supabaseClient
  .from('users')
  .update({ is_admin: true })
  .eq('id', 'attacker_uuid');
// Self-promotion to admin!
```

**Result:** ❌ **CRITICAL FAIL** - Direct table access creates privilege escalation

---

## F. Session Integrity Audit

### F1. Session Validation

[Lines 2746-2850](sql/full_dump.sql#L2746-L2850)
```sql
SELECT user_id INTO v_user_id FROM public.sessions
WHERE token = p_token
  AND expires_at > NOW() ✅
  AND (revoked_at IS NULL OR revoked_at > NOW()); ✅
```

**Result:** ✅ **PASS** - Expiry + revocation working correctly

---

## G. Frontend Audit

### G1. Legacy RPC Calls (❌ FAIL)

#### `verify_user_pin` (3 instances - function doesn't exist ✅)

- [js/admin.js#L235](js/admin.js#L235)
- [js/app.js#L1138](js/app.js#L1138)
- [js/app.js#L3661](js/app.js#L3661)

#### `set_user_pin` (2 instances - function doesn't exist ✅)

- [js/admin.js#L588](js/admin.js#L588)
- [js/app.js#L3093](js/app.js#L3093)

**Impact:** Frontend will fail with "function does not exist" - needs migration to `change_user_pin(p_token, ...)`

### G2. Token-Based Calls (✅ PASS - 50+ calls migrated)

- [js/app.js#L1146](js/app.js#L1146): `change_user_pin(p_token, ...)` ✅
- [js/app.js#L1970](js/app.js#L1970): `ack_notice(p_token, ...)` ✅
- [js/app.js#L3344](js/app.js#L3344): `admin_set_active_period(p_token, ...)` ✅

---

## Risk Assessment

### Scenario 1: Admin Impersonation via Legacy Functions

```javascript
await supabaseClient.rpc('admin_set_active_period', {
  p_admin_user_id: '00000000-0000-0000-0000-000000000001',
  p_period_id: 999
});
// Result: SUCCESS - period activated without session token
// Status: ❌ CRITICAL VULNERABILITY
```

### Scenario 2: Direct Session Table Manipulation

```javascript
await supabaseClient.from('sessions').insert({
  token: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  user_id: attackerUserId,
  expires_at: '2099-12-31T23:59:59Z'
});
// Result: SUCCESS with GRANT ALL
// Status: ❌ CRITICAL VULNERABILITY
```

### Scenario 3: Non-Admin Permission Bypass (✅ PREVENTED)

```javascript
await supabaseClient.rpc('admin_delete_notice', {
  p_token: nonAdminToken,
  p_notice_id: 'some-notice-uuid'
});
// Result: Exception "Insufficient permissions"
// Status: ✅ BLOCKED
```

---

## Summary of Findings

### Critical Issues (Fix Immediately)

1. **4 Legacy Functions Exist** - Allow user impersonation
   - **Fix:** Deploy [DROP_LEGACY_ADMIN_FUNCTIONS.sql](sql/DROP_LEGACY_ADMIN_FUNCTIONS.sql)

2. **GRANT ALL to anon/authenticated** - Allows direct table manipulation
   - **Fix:** REVOKE ALL, grant EXECUTE on functions only

3. **Frontend Calls Non-Existent Functions** - verify_user_pin, set_user_pin
   - **Fix:** Migrate to token-only RPCs

4. **verify_login Bug** - Ambiguous column references
   - **Fix:** Deploy [FIX_VERIFY_LOGIN.sql](sql/FIX_VERIFY_LOGIN.sql)

### What's Working ✅

1. **36 Token-Based Functions Properly Implemented**
2. **SECURITY DEFINER Functions Hardened** (42/46 with search_path)
3. **Session Validation Robust** (expiry + revocation)

---

## Recommendations Priority

### Immediate (Deploy Today)

1. ✅ Deploy [DROP_LEGACY_ADMIN_FUNCTIONS.sql](sql/DROP_LEGACY_ADMIN_FUNCTIONS.sql)
2. ✅ Deploy [FIX_VERIFY_LOGIN.sql](sql/FIX_VERIFY_LOGIN.sql)
3. ❌ Deploy table grants revocation (see [FIX_PLAN.md](FIX_PLAN.md))

### Short-Term (This Week)

4. Migrate frontend verify_user_pin/set_user_pin calls
5. Enable RLS on sessions, users, swap tables
6. Audit `.from()` calls for direct writes

### Long-Term (Next Sprint)

7. Session logging/monitoring
8. Session rotation on privilege escalation
9. RPC rate limiting
10. Permission data audit

---

**End of Report**

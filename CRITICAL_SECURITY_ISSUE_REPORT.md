# 🚨 CRITICAL SECURITY ISSUE - IMMEDIATE ACTION REQUIRED

**Date**: January 16, 2026  
**Severity**: CRITICAL - Security Vulnerability  
**Status**: UNRESOLVED - Requires Manual Remediation  

---

## EXECUTIVE SUMMARY

Your token-only authentication migration has a **CRITICAL FLAW**:

**The migrated RPC functions were created with BOTH old and new authentication parameters in the same function signature.**

This means:
- ✅ They accept `p_token` (new token-based auth)
- ❌ They ALSO accept `p_admin_id`, `p_user_id`, `p_pin` (old PIN-based auth)
- 🔓 **Clients can authenticate with EITHER method**
- 🚨 **Your new security controls are BYPASSED**

---

## THE PROBLEM (25 Functions Affected)

These 25 functions have been created with MIXED parameters:

### Admin Functions (13):
- ❌ `admin_clear_request_cell(p_token, p_admin_id, p_pin, ...)` 
- ❌ `admin_create_five_week_period(p_admin_id, p_pin, p_name, ...)`
- ❌ `admin_execute_shift_swap(p_admin_id, p_token, p_pin, ...)`
- ❌ `admin_get_swap_executions(p_admin_id, p_token, p_pin, ...)`
- ❌ `admin_lock_request_cell(p_token, p_admin_id, p_pin, ...)`
- ❌ `admin_notice_ack_counts(p_admin_id, p_pin, ...)`
- ❌ `admin_set_period_closes_at(p_token, p_admin_id, p_pin, ...)`
- ❌ `admin_set_request_cell(p_token, p_admin_id, p_pin, ...)`
- ❌ `admin_set_week_open_flags(p_token, p_admin_id, p_pin, ...)`
- ❌ `admin_unlock_request_cell(p_token, p_admin_id, p_pin, ...)`
- ❌ `admin_upsert_notice(p_admin_id, p_token, p_pin, ...)`
- ❌ `admin_reorder_users(p_token, p_user_id, ...)`
- ❌ `admin_set_user_active(p_token, p_user_id, ...)`
- ❌ `admin_set_user_pin(p_token, p_user_id, ...)`
- ❌ `admin_upsert_user(p_token, p_user_id, ...)`

### Staff Functions (12):
- ❌ `change_user_pin(p_user_id, p_pin, ...)`
- ❌ `get_week_comments(p_week_id, p_user_id, p_pin, ...)`
- ❌ `log_rota_assignment_audit(p_period_id, p_user_id, ...)`
- ❌ `save_request_with_pin(p_token, p_date, p_user_id, ...)`
- ❌ `set_user_active(p_user_id, p_active, ...)`
- ❌ `set_user_admin(p_user_id, ...)`
- ❌ `set_user_language(p_user_id, p_pin, ...)`
- ❌ `set_user_pin(p_user_id, p_pin, ...)`
- ❌ `upsert_request_with_pin(p_token, p_date, p_user_id, ...)`
- ❌ `upsert_week_comment(p_user_id, p_pin, ...)`

---

## WHY THIS HAPPENED

The migration SQL script used `CREATE OR REPLACE FUNCTION`, which in PostgreSQL:
1. Can only modify the function body, NOT parameter types/names
2. Cannot change parameter order
3. Creates a NEW overload if signatures don't match exactly

**Result**: Instead of replacing old functions, it created **mixed parameter** versions where BOTH old and new authentication methods work.

---

## IMMEDIATE RISK ASSESSMENT

| Risk | Severity | Impact |
|------|----------|--------|
| PIN-based auth still works | 🔴 CRITICAL | Bypasses JWT token requirement |
| Clients can use either auth method | 🔴 CRITICAL | No forced migration to tokens |
| Session validation not required | 🔴 CRITICAL | Tokens not verified |
| No audit trail of which auth used | 🟠 HIGH | Can't track legacy auth usage |

---

## REMEDIATION REQUIRED

### Option 1: DROP and RECREATE (RECOMMENDED)
1. Drop all 25 affected functions
2. Verify they're gone
3. Re-run the corrected migration SQL
4. Test thoroughly

### Option 2: Manual Individual Fixes
- Would require rewriting each function signature manually
- Much more error-prone
- Not recommended given the scope

---

## NEXT STEPS (DO THIS NOW)

### Step 1: Backup Current State
```sql
-- Export current function definitions for backup
\d+ admin_clear_request_cell
\d+ admin_execute_shift_swap
-- ... etc for all 25 functions
```

### Step 2: DROP ALL 25 AFFECTED FUNCTIONS
```sql
DROP FUNCTION IF EXISTS admin_clear_request_cell CASCADE;
DROP FUNCTION IF EXISTS admin_execute_shift_swap CASCADE;
-- ... (see complete list below)
```

### Step 3: VERIFY THEY'RE GONE
```sql
SELECT COUNT(*) FROM information_schema.routines
WHERE routine_name IN (list of 25 functions above);
-- Result should be: 0
```

### Step 4: RE-CREATE WITH CORRECT SIGNATURES
Run the corrected migration SQL that creates proper token-only versions

### Step 5: VERIFY SECURITY
```sql
-- Should return 0 (no legacy params remain)
SELECT COUNT(*) FROM information_schema.parameters
WHERE parameter_name IN ('p_user_id', 'p_pin', 'p_admin_id')
  AND specific_schema = 'public';
```

---

## ROOT CAUSE ANALYSIS

The original migration script (`migrate_to_token_only_rpcs.sql`) attempted to use `CREATE OR REPLACE FUNCTION` to change function signatures. **This approach fundamentally cannot work in PostgreSQL** because:

1. `CREATE OR REPLACE` can only change the function body
2. It cannot change, add, or remove parameters
3. When parameter types/names differ, PostgreSQL creates a new OVERLOAD instead of replacing

**Correct Approach Should Have Been**:
1. Drop all old function versions first (explicitly)
2. Then CREATE the new versions
3. This is what should happen next

---

## COMPLETE LIST: 25 FUNCTIONS TO DROP

```sql
-- Admin functions
DROP FUNCTION IF EXISTS admin_clear_request_cell CASCADE;
DROP FUNCTION IF EXISTS admin_create_five_week_period CASCADE;
DROP FUNCTION IF EXISTS admin_execute_shift_swap CASCADE;
DROP FUNCTION IF EXISTS admin_get_swap_executions CASCADE;
DROP FUNCTION IF EXISTS admin_lock_request_cell CASCADE;
DROP FUNCTION IF EXISTS admin_notice_ack_counts CASCADE;
DROP FUNCTION IF EXISTS admin_reorder_users CASCADE;
DROP FUNCTION IF EXISTS admin_set_period_closes_at CASCADE;
DROP FUNCTION IF EXISTS admin_set_request_cell CASCADE;
DROP FUNCTION IF EXISTS admin_set_user_active CASCADE;
DROP FUNCTION IF EXISTS admin_set_user_pin CASCADE;
DROP FUNCTION IF EXISTS admin_set_week_open_flags CASCADE;
DROP FUNCTION IF EXISTS admin_unlock_request_cell CASCADE;
DROP FUNCTION IF EXISTS admin_upsert_notice CASCADE;
DROP FUNCTION IF EXISTS admin_upsert_user CASCADE;

-- Staff functions
DROP FUNCTION IF EXISTS change_user_pin CASCADE;
DROP FUNCTION IF EXISTS get_week_comments CASCADE;
DROP FUNCTION IF EXISTS log_rota_assignment_audit CASCADE;
DROP FUNCTION IF EXISTS save_request_with_pin CASCADE;
DROP FUNCTION IF EXISTS set_user_active CASCADE;
DROP FUNCTION IF EXISTS set_user_admin CASCADE;
DROP FUNCTION IF EXISTS set_user_language CASCADE;
DROP FUNCTION IF EXISTS set_user_pin CASCADE;
DROP FUNCTION IF EXISTS upsert_request_with_pin CASCADE;
DROP FUNCTION IF EXISTS upsert_week_comment CASCADE;
```

---

## WHAT I'VE IDENTIFIED

✅ **Discovery**: Found all 25 functions with mixed authentication parameters  
✅ **Analysis**: Root cause identified (CREATE OR REPLACE limitation)  
✅ **Risk**: Assessed as CRITICAL - legacy auth still accessible  
✅ **Solution**: Clear remediation path provided  
❌ **Implementation**: Requires your authorization and execution  

---

## DECISION REQUIRED

**This is a critical security issue that MUST be resolved before production use.**

### You have two choices:

**A) FIX NOW (Recommended)**
- Time: 30 minutes
- Risk: Low (procedure is straightforward)
- Outcome: Secure token-only authentication

**B) ACCEPT RISK (Not recommended)**
- Continue with mixed auth (both PIN and token work)
- Legacy authentication can be used to bypass new security
- No forced migration for clients

---

## CONTACT & ESCALATION

This is beyond automated migration - **requires human decision on how to proceed**.

Recommendation: **Choose Option A (FIX NOW)** and I'll execute the complete remediation in the next phase.


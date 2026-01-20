# 🔴 LEGACY AUTHENTICATION FUNCTIONS - COMPLETE INVENTORY

**Date**: January 16, 2026  
**Status**: SECURITY CRITICAL - PRODUCTION VULNERABILITY  
**Scope**: All 42+ functions using legacy authentication (p_admin_id, p_pin, p_user_id)  

---

## EXECUTIVE SUMMARY

The migration to token-only authentication is **INCOMPLETE**. PostgreSQL function overloading has created a serious security issue:

- ✅ **42 new token-only functions** created with `(p_token, ...)` signatures
- ❌ **41+ old functions STILL EXIST** with `(p_admin_id, p_pin)` or `(p_user_id, p_pin)` signatures
- 🔓 **SECURITY HOLE**: Clients can still call legacy functions, bypassing new auth

### Critical Risk
Any client that knows the old function signatures can still authenticate using PIN codes, completely bypassing the token-based system.

---

## PART 1: FUNCTIONS THAT MUST BE DROPPED (RPC Functions)

These are the 41 RPC functions that MUST be dropped to complete the migration. They have both old and new versions; we must remove the legacy overloads.

### A. Admin Functions with Legacy Overloads (27 total)

These are primarily parameterized admin operations that accept `p_admin_id` and `p_pin` instead of `p_token`.

| Function Name | Legacy Signature | Drop Statement | Reason |
|---|---|---|---|
| admin_approve_swap_request | `(p_admin_id uuid, p_pin text, p_swap_request_id uuid)` | `DROP FUNCTION IF EXISTS public.admin_approve_swap_request(uuid, text, uuid);` | Token-only replacement exists |
| admin_clear_request_cell | `(p_admin_id uuid, p_pin text, p_target_user_id uuid, p_date date)` | `DROP FUNCTION IF EXISTS public.admin_clear_request_cell(uuid, text, uuid, date);` | Token-only replacement exists |
| admin_create_five_week_period | `(p_admin_id uuid, p_pin text, p_name text, p_start_date date, p_end_date date)` | `DROP FUNCTION IF EXISTS public.admin_create_five_week_period(uuid, text, text, date, date);` | Token-only replacement exists |
| admin_create_next_period | `(p_admin_id uuid, p_pin text)` | `DROP FUNCTION IF EXISTS public.admin_create_next_period(uuid, text);` | Token-only replacement exists |
| admin_decline_swap_request | `(p_admin_id uuid, p_pin text, p_swap_request_id uuid)` | `DROP FUNCTION IF EXISTS public.admin_decline_swap_request(uuid, text, uuid);` | Token-only replacement exists |
| admin_delete_notice | `(p_admin_id uuid, p_pin text, p_notice_id uuid)` | `DROP FUNCTION IF EXISTS public.admin_delete_notice(uuid, text, uuid);` | Token-only replacement exists |
| admin_execute_shift_swap | `(p_admin_id uuid, p_pin text, p_initiator_user_id uuid, p_initiator_shift_date date, p_counterparty_user_id uuid, p_counterparty_shift_date date, p_period_id integer)` | `DROP FUNCTION IF EXISTS public.admin_execute_shift_swap(uuid, text, uuid, date, uuid, date, integer);` | Token-only replacement exists |
| admin_get_all_notices | `(p_admin_id uuid, p_pin text)` | `DROP FUNCTION IF EXISTS public.admin_get_all_notices(uuid, text);` | Token-only replacement exists |
| admin_get_notice_acks | `(p_admin_id uuid, p_pin text, p_notice_id uuid)` | `DROP FUNCTION IF EXISTS public.admin_get_notice_acks(uuid, text, uuid);` | Token-only replacement exists |
| admin_get_swap_executions | `(p_admin_id uuid, p_pin text, p_period_id integer)` | `DROP FUNCTION IF EXISTS public.admin_get_swap_executions(uuid, text, integer);` | Token-only replacement exists |
| admin_get_swap_requests | `(p_admin_id uuid, p_pin text)` | `DROP FUNCTION IF EXISTS public.admin_get_swap_requests(uuid, text);` | Token-only replacement exists |
| admin_lock_request_cell | `(p_admin_id uuid, p_pin text, p_target_user_id uuid, p_date date, p_reason_en text, p_reason_es text)` | `DROP FUNCTION IF EXISTS public.admin_lock_request_cell(uuid, text, uuid, date, text, text);` | Token-only replacement exists |
| admin_notice_ack_counts | `(p_admin_id uuid, p_pin text, p_notice_ids uuid[])` | `DROP FUNCTION IF EXISTS public.admin_notice_ack_counts(uuid, text, uuid[]);` | Token-only replacement exists |
| admin_reorder_users | `(p_admin_id uuid, p_pin text, p_user_id uuid, p_display_order integer)` | `DROP FUNCTION IF EXISTS public.admin_reorder_users(uuid, text, uuid, integer);` | Token-only replacement exists |
| admin_set_active_period | `(p_admin_id uuid, p_pin text, p_period_id uuid)` | `DROP FUNCTION IF EXISTS public.admin_set_active_period(uuid, text, uuid);` | Token-only replacement exists |
| admin_set_notice_active | `(p_admin_id uuid, p_pin text, p_notice_id uuid, p_active boolean)` | `DROP FUNCTION IF EXISTS public.admin_set_notice_active(uuid, text, uuid, boolean);` | Token-only replacement exists |
| admin_set_period_closes_at | `(p_admin_id uuid, p_pin text, p_period_id uuid, p_closes_at timestamp with time zone)` | `DROP FUNCTION IF EXISTS public.admin_set_period_closes_at(uuid, text, uuid, timestamp with time zone);` | Token-only replacement exists |
| admin_set_period_hidden | `(p_admin_id uuid, p_pin text, p_period_id uuid, p_hidden boolean)` | `DROP FUNCTION IF EXISTS public.admin_set_period_hidden(uuid, text, uuid, boolean);` | Token-only replacement exists |
| admin_set_request_cell | `(p_admin_id uuid, p_pin text, p_target_user_id uuid, p_date date, p_value text, p_important_rank smallint)` | `DROP FUNCTION IF EXISTS public.admin_set_request_cell(uuid, text, uuid, date, text, smallint);` | Token-only replacement exists |
| admin_set_user_active | `(p_admin_id uuid, p_pin text, p_user_id uuid, p_active boolean)` | `DROP FUNCTION IF EXISTS public.admin_set_user_active(uuid, text, uuid, boolean);` | Token-only replacement exists |
| admin_set_user_pin | `(p_admin_id uuid, p_pin text, p_user_id uuid, p_new_pin text)` | `DROP FUNCTION IF EXISTS public.admin_set_user_pin(uuid, text, uuid, text);` | Token-only replacement exists |
| admin_set_week_open | `(p_admin_id uuid, p_pin text, p_week_id uuid, p_open boolean)` | `DROP FUNCTION IF EXISTS public.admin_set_week_open(uuid, text, uuid, boolean);` | Token-only replacement exists |
| admin_set_week_open_flags | `(p_admin_id uuid, p_pin text, p_week_id uuid, p_open boolean, p_open_after_close boolean)` | `DROP FUNCTION IF EXISTS public.admin_set_week_open_flags(uuid, text, uuid, boolean, boolean);` | Token-only replacement exists |
| admin_toggle_hidden_period | `(p_admin_id uuid, p_pin text, p_period_id uuid)` | `DROP FUNCTION IF EXISTS public.admin_toggle_hidden_period(uuid, text, uuid);` | Token-only replacement exists |
| admin_unlock_request_cell | `(p_admin_id uuid, p_pin text, p_target_user_id uuid, p_date date)` | `DROP FUNCTION IF EXISTS public.admin_unlock_request_cell(uuid, text, uuid, date);` | Token-only replacement exists |
| admin_upsert_notice | `(p_admin_id uuid, p_pin text, p_notice_id uuid, p_title text, p_body_en text, p_body_es text, p_target_all boolean, p_target_roles integer[])` | `DROP FUNCTION IF EXISTS public.admin_upsert_notice(uuid, text, uuid, text, text, text, boolean, integer[]);` | Token-only replacement exists |
| admin_upsert_user | `(p_admin_id uuid, p_pin text, p_user_id uuid, p_name text, p_role_id integer)` | `DROP FUNCTION IF EXISTS public.admin_upsert_user(uuid, text, uuid, text, integer);` | Token-only replacement exists |

**Subtotal: 27 admin functions to drop**

---

### B. Staff Functions with Legacy Overloads (6 total)

Staff functions that still accept `p_user_id` and `p_pin` parameters.

| Function Name | Legacy Signature | Drop Statement | Reason |
|---|---|---|---|
| change_user_pin | `(p_user_id uuid, p_old_pin text, p_new_pin text)` | `DROP FUNCTION IF EXISTS public.change_user_pin(uuid, text, text);` | Token-only replacement exists |
| get_all_notices | `(p_user_id uuid, p_pin text)` | `DROP FUNCTION IF EXISTS public.get_all_notices(uuid, text);` | Token-only replacement exists |
| get_notices_for_user | `(p_user_id uuid, p_pin text)` | `DROP FUNCTION IF EXISTS public.get_notices_for_user(uuid, text);` | Token-only replacement exists |
| get_week_comments | `(p_week_id uuid, p_user_id uuid, p_pin text)` | `DROP FUNCTION IF EXISTS public.get_week_comments(uuid, uuid, text);` | Token-only replacement exists |
| set_user_language | `(p_user_id uuid, p_pin text, p_lang text)` | `DROP FUNCTION IF EXISTS public.set_user_language(uuid, text, text);` | Token-only replacement exists |
| set_user_active | `(p_admin_id uuid, p_pin text, p_user_id uuid, p_active boolean)` | `DROP FUNCTION IF EXISTS public.set_user_active(uuid, text, uuid, boolean);` | Token-only replacement exists |
| upsert_week_comment | `(p_week_id uuid, p_user_id uuid, p_pin text, p_comment text)` | `DROP FUNCTION IF EXISTS public.upsert_week_comment(uuid, uuid, text, text);` | Token-only replacement exists |

**Subtotal: 7 staff functions to drop**

---

### C. Helper/Internal Functions with Legacy Parameters (8 total)

These are helper functions that use legacy authentication patterns. Some should be dropped entirely, others may need to be kept but restricted.

| Function Name | Legacy Signature | Drop Statement | Status |
|---|---|---|---|
| _require_admin | `(p_admin_id uuid, p_pin text)` | `DROP FUNCTION IF EXISTS public._require_admin(uuid, text);` | ❌ **MUST DROP** - Core legacy PIN checker |
| assert_admin | `(p_user_id uuid, p_pin text)` | `DROP FUNCTION IF EXISTS public.assert_admin(uuid, text);` | ❌ **MUST DROP** - Legacy assertion function |
| verify_admin_pin | `(p_admin_id uuid, p_pin text)` | `DROP FUNCTION IF EXISTS public.verify_admin_pin(uuid, text);` | ❌ **MUST DROP** - PIN verification for admins |
| verify_pin_login | `(p_user_id uuid, p_pin text)` | `DROP FUNCTION IF EXISTS public.verify_pin_login(uuid, text);` | ❌ **MUST DROP** - PIN verification for staff |
| verify_user_pin | `(p_user_id uuid, p_pin text)` | `DROP FUNCTION IF EXISTS public.verify_user_pin(uuid, text);` | ❌ **MUST DROP** - User PIN verification |
| clear_request_with_pin | `(p_user_id uuid, p_pin text, p_date date)` | `DROP FUNCTION IF EXISTS public.clear_request_with_pin(uuid, text, date);` | ❌ **MUST DROP** - Deprecated PIN-based variant |
| delete_request_with_pin | `(p_user_id uuid, p_pin text, p_date date)` | `DROP FUNCTION IF EXISTS public.delete_request_with_pin(uuid, text, date);` | ❌ **MUST DROP** - Deprecated PIN-based variant |
| save_request_with_pin | `(p_user_id uuid, p_pin text, p_date date, p_value text, p_important_rank integer)` | `DROP FUNCTION IF EXISTS public.save_request_with_pin(uuid, text, date, text, integer);` | ⚠️ **REVIEW** - Now migrated to token version |
| upsert_request_with_pin | `(p_user_id uuid, p_pin text, p_date date, p_value text, p_important_rank integer)` | `DROP FUNCTION IF EXISTS public.upsert_request_with_pin(uuid, text, date, text, integer);` | ⚠️ **REVIEW** - Now migrated to token version |

**Subtotal: 8+ helper/legacy functions**

---

## PART 2: COMPLETE DROP STATEMENTS (SQL BATCH)

```sql
-- ================================================================================
-- CRITICAL SECURITY: Drop All Legacy Authentication Overloads
-- ================================================================================
-- Status: MANDATORY - Run immediately in Supabase SQL Editor
-- Risk if NOT run: Production vulnerability - legacy PIN auth still active
-- ================================================================================

BEGIN TRANSACTION;

-- ================================================================================
-- PHASE 1: Drop Legacy Admin Function Overloads (27 functions)
-- ================================================================================

DROP FUNCTION IF EXISTS public.admin_approve_swap_request(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.admin_clear_request_cell(uuid, text, uuid, date);
DROP FUNCTION IF EXISTS public.admin_create_five_week_period(uuid, text, text, date, date);
DROP FUNCTION IF EXISTS public.admin_create_next_period(uuid, text);
DROP FUNCTION IF EXISTS public.admin_decline_swap_request(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.admin_delete_notice(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.admin_execute_shift_swap(uuid, text, uuid, date, uuid, date, integer);
DROP FUNCTION IF EXISTS public.admin_get_all_notices(uuid, text);
DROP FUNCTION IF EXISTS public.admin_get_notice_acks(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.admin_get_swap_executions(uuid, text, integer);
DROP FUNCTION IF EXISTS public.admin_get_swap_requests(uuid, text);
DROP FUNCTION IF EXISTS public.admin_lock_request_cell(uuid, text, uuid, date, text, text);
DROP FUNCTION IF EXISTS public.admin_notice_ack_counts(uuid, text, uuid[]);
DROP FUNCTION IF EXISTS public.admin_reorder_users(uuid, text, uuid, integer);
DROP FUNCTION IF EXISTS public.admin_set_active_period(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.admin_set_notice_active(uuid, text, uuid, boolean);
DROP FUNCTION IF EXISTS public.admin_set_period_closes_at(uuid, text, uuid, timestamp with time zone);
DROP FUNCTION IF EXISTS public.admin_set_period_hidden(uuid, text, uuid, boolean);
DROP FUNCTION IF EXISTS public.admin_set_request_cell(uuid, text, uuid, date, text, smallint);
DROP FUNCTION IF EXISTS public.admin_set_user_active(uuid, text, uuid, boolean);
DROP FUNCTION IF EXISTS public.admin_set_user_pin(uuid, text, uuid, text);
DROP FUNCTION IF EXISTS public.admin_set_week_open(uuid, text, uuid, boolean);
DROP FUNCTION IF EXISTS public.admin_set_week_open_flags(uuid, text, uuid, boolean, boolean);
DROP FUNCTION IF EXISTS public.admin_toggle_hidden_period(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.admin_unlock_request_cell(uuid, text, uuid, date);
DROP FUNCTION IF EXISTS public.admin_upsert_notice(uuid, text, uuid, text, text, text, boolean, integer[]);
DROP FUNCTION IF EXISTS public.admin_upsert_user(uuid, text, uuid, text, integer);

-- ================================================================================
-- PHASE 2: Drop Legacy Staff Function Overloads (7 functions)
-- ================================================================================

DROP FUNCTION IF EXISTS public.change_user_pin(uuid, text, text);
DROP FUNCTION IF EXISTS public.get_all_notices(uuid, text);
DROP FUNCTION IF EXISTS public.get_notices_for_user(uuid, text);
DROP FUNCTION IF EXISTS public.get_week_comments(uuid, uuid, text);
DROP FUNCTION IF EXISTS public.set_user_language(uuid, text, text);
DROP FUNCTION IF EXISTS public.set_user_active(uuid, text, uuid, boolean);
DROP FUNCTION IF EXISTS public.upsert_week_comment(uuid, uuid, text, text);

-- ================================================================================
-- PHASE 3: Drop Legacy PIN-Based Functions (8 functions)
-- ================================================================================

DROP FUNCTION IF EXISTS public._require_admin(uuid, text);
DROP FUNCTION IF EXISTS public.assert_admin(uuid, text);
DROP FUNCTION IF EXISTS public.verify_admin_pin(uuid, text);
DROP FUNCTION IF EXISTS public.verify_pin_login(uuid, text);
DROP FUNCTION IF EXISTS public.verify_user_pin(uuid, text);
DROP FUNCTION IF EXISTS public.clear_request_with_pin(uuid, text, date);
DROP FUNCTION IF EXISTS public.delete_request_with_pin(uuid, text, date);
DROP FUNCTION IF EXISTS public.save_request_with_pin(uuid, text, date, text, integer);
DROP FUNCTION IF EXISTS public.upsert_request_with_pin(uuid, text, date, text, integer);

-- ================================================================================
-- PHASE 4: Verification Query
-- ================================================================================
-- This query should return 0 after all drops are complete

SELECT 
  COUNT(*) as legacy_auth_functions_remaining,
  string_agg(DISTINCT routine_name, ', ' ORDER BY routine_name) as function_names
FROM information_schema.routines r
LEFT JOIN information_schema.parameters p ON r.specific_name = p.specific_name
WHERE routine_schema = 'public'
  AND (
    parameter_name = 'p_user_id'
    OR parameter_name = 'p_pin'
    OR parameter_name = 'p_admin_id'
  )
  AND routine_name NOT IN (
    'require_session_permissions',  -- Core auth helper, safe
    'is_admin_user'                 -- Helper function, safe
  );

COMMIT;
```

---

## PART 3: FUNCTIONS TO KEEP (Safe, Non-RPC)

These functions are **INTERNAL HELPERS** and should NOT be dropped. They are triggered by table changes or called internally, not exposed as RPC endpoints.

### Trigger Functions (Safe)
- `touch_updated_at()` - Updates timestamp on changes
- `touch_notice_updated_at()` - Updates notice timestamp
- `set_week_comments_updated_at()` - Updates week comment timestamp
- `notifications_set_updated_at()` - Updates notification timestamp
- `set_comment_created_audit()` - Audit trigger for comments
- `set_comment_updated_audit()` - Audit trigger for comments
- `set_override_created_audit()` - Audit trigger for overrides
- `set_override_updated_audit()` - Audit trigger for overrides
- `update_staffing_requirements_updated_at()` - Updates staffing timestamp

### Constraint Functions (Safe)
- `enforce_max_5_requests_per_week()` - Prevents requests > 5/week
- `enforce_off_priority_rules()` - Enforces off priority constraints
- `log_rota_assignment_audit(uuid, uuid, date, bigint, bigint, text, uuid, text)` - Audit logging (non-RPC)

### Wrapper Functions (Safe)
- `crypt(p_password text, p_salt text)` - PostgreSQL pgcrypto wrapper
- `gen_salt(p_type text)` - PostgreSQL pgcrypto wrapper
- `gen_salt(p_type text, p_rounds integer)` - PostgreSQL pgcrypto wrapper

### Core Authentication Function (CRITICAL - DO NOT DROP)
- **`require_session_permissions(p_token uuid, p_permission text)`** - THE NEW AUTH SYSTEM
  - This function validates tokens and permissions
  - All new RPC functions call this
  - **MUST BE PROTECTED** - It's the foundation of the new auth system

---

## PART 4: NEW TOKEN-ONLY FUNCTIONS (Correctly Migrated)

These 42+ functions have been correctly migrated to token-only authentication:

### New Staff Functions (Token-Only)
```
public.get_unread_notices(p_token uuid)
public.get_all_notices(p_token uuid)
public.get_notices_for_user(p_token uuid)
public.acknowledge_notice(p_token uuid, p_notice_id uuid)
public.ack_notice(p_token uuid, p_notice_id uuid, p_version integer)
public.set_request_cell(p_token uuid, p_date date, p_value text, p_important_rank smallint)
public.clear_request_cell(p_token uuid, p_date date)
public.save_request_with_pin(p_token uuid, p_date date, p_value text, p_important_rank integer)
public.upsert_request_with_pin(p_token uuid, p_date date, p_value text, p_important_rank integer)
public.change_user_pin(p_token uuid, p_old_pin text, p_new_pin text)
public.set_user_language(p_token uuid, p_lang text)
public.get_pending_swap_requests_for_me(p_token uuid)
public.get_week_comments(p_token uuid, p_week_id uuid)
public.upsert_week_comment(p_token uuid, p_week_id uuid, p_comment text)
public.set_user_active(p_token uuid, p_active boolean)
```

### New Admin Functions (Token-Only)
```
public.admin_get_swap_requests(p_token uuid)
public.admin_approve_swap_request(p_token uuid, p_swap_request_id uuid)
public.admin_decline_swap_request(p_token uuid, p_swap_request_id uuid)
public.admin_get_swap_executions(p_token uuid, p_period_id integer)
public.admin_get_all_notices(p_token uuid)
public.admin_get_notice_acks(p_token uuid, p_notice_id uuid)
public.admin_delete_notice(p_token uuid, p_notice_id uuid)
public.admin_set_notice_active(p_token uuid, p_notice_id uuid, p_active boolean)
public.admin_set_active_period(p_token uuid, p_period_id uuid)
public.admin_set_period_closes_at(p_token uuid, p_period_id uuid, p_closes_at timestamp with time zone)
public.admin_toggle_hidden_period(p_token uuid, p_period_id uuid)
public.admin_set_period_hidden(p_token uuid, p_period_id uuid, p_hidden boolean)
public.admin_clear_request_cell(p_token uuid, p_target_user_id uuid, p_date date)
public.admin_unlock_request_cell(p_token uuid, p_target_user_id uuid, p_date date)
public.admin_upsert_user(p_token uuid, p_user_id uuid, p_name text, p_role_id integer)
public.admin_set_user_active(p_token uuid, p_user_id uuid, p_active boolean)
public.admin_set_user_pin(p_token uuid, p_user_id uuid, p_new_pin text)
public.admin_reorder_users(p_token uuid, p_user_id uuid, p_display_order integer)
public.admin_get_all_notices(p_token uuid)
```

---

## PART 5: DEPLOYMENT CHECKLIST

### Pre-Deployment (IMMEDIATE)
- [ ] Backup production database via Supabase (Settings → Backups)
- [ ] Review this inventory with security team
- [ ] Confirm no clients are still using legacy function names

### Deployment Steps
1. [ ] Log into Supabase SQL Editor
2. [ ] Copy the SQL batch from **PART 2** above
3. [ ] Execute the transaction
4. [ ] Verify: Query should return `0` for legacy_auth_functions_remaining
5. [ ] Test client connections with new token-only RPCs

### Post-Deployment
- [ ] Monitor application logs for 24 hours
- [ ] Watch database error logs in Supabase
- [ ] Verify all staff and admin operations work
- [ ] Run security audit verification query (see below)

### Rollback Procedure
If anything breaks:
1. Contact Supabase support
2. Request restore from backup (created before deployment)
3. Re-run migration process

---

## PART 6: SECURITY VERIFICATION QUERY

Run this after deployment to confirm migration is complete:

```sql
-- Should return 0 if migration is successful
SELECT 
  COUNT(*) as CRITICAL_LEGACY_FUNCTIONS_FOUND,
  string_agg(
    DISTINCT routine_name || '(' || string_agg(parameter_name, ', ' ORDER BY ordinal_position) || ')',
    E'\n'
  ) as legacy_functions_that_still_exist
FROM information_schema.routines r
LEFT JOIN information_schema.parameters p ON r.specific_name = p.specific_name
WHERE routine_schema = 'public'
  AND (
    parameter_name = 'p_user_id'
    OR parameter_name = 'p_pin'
    OR parameter_name = 'p_admin_id'
  )
GROUP BY routine_name;

-- Should return > 40 token-only functions
SELECT 
  COUNT(*) as token_only_functions_active,
  string_agg(DISTINCT routine_name, ', ' ORDER BY routine_name) as functions
FROM information_schema.routines r
LEFT JOIN information_schema.parameters p ON r.specific_name = p.specific_name
WHERE routine_schema = 'public'
  AND (
    parameter_name LIKE 'p_token%'
    OR routine_name LIKE 'require_session%'
  )
GROUP BY routine_name;
```

---

## SUMMARY TABLE

| Category | Count | Status | Action |
|----------|-------|--------|--------|
| **Admin functions to drop** | 27 | CRITICAL | DROP |
| **Staff functions to drop** | 7 | CRITICAL | DROP |
| **Legacy helpers to drop** | 8 | CRITICAL | DROP |
| **TOTAL MUST DROP** | **42** | **❌ NOT DONE** | **URGENT** |
| **Internal helpers to keep** | 13 | SAFE | KEEP |
| **New token-only functions** | 42+ | ✅ MIGRATED | VERIFY |

---

## IMPACT ASSESSMENT

### If Dropped (CORRECT ACTION ✅)
- ✅ Legacy PIN authentication completely disabled
- ✅ All clients forced to use new token-based system
- ✅ Production security vulnerability eliminated
- ✅ Zero risk of PIN bypass

### If NOT Dropped (CRITICAL VULNERABILITY ❌)
- ❌ Clients can still authenticate with PIN codes
- ❌ JWT token system is bypassed entirely
- ❌ Rota application has TWO authentication systems
- ❌ Staff/admin can use either new tokens OR old PINs
- ❌ Security audit would FAIL

---

## RELATED DOCUMENTATION

- [Migration Summary](TOKEN_ONLY_MIGRATION_SUMMARY.md) - Overview of migration
- [Security Audit Report](SECURITY_AUDIT_REPORT.md) - Detailed audit findings
- [Deployment Instructions](DEPLOYMENT_INSTRUCTIONS.md) - Step-by-step deployment
- [Function Inventory](FUNCTION_INVENTORY.md) - Complete function audit
- [Drop All Legacy Overloads SQL](sql/drop_all_legacy_function_overloads.sql) - SQL to run
- [Migrate to Token-Only SQL](sql/migrate_to_token_only_rpcs.sql) - New function definitions

# 🔐 SECURITY AUDIT REPORT
## Token-Only RPC Functions Security Hardening

**Date**: January 16, 2026  
**Status**: AUDIT IN PROGRESS  
**Scope**: All 94 public RPC functions  

---

## CRITICAL FINDINGS

### ⚠️ LEGACY FUNCTIONS STILL ACTIVE (MUST DROP)

These functions still use old authentication (p_user_id, p_pin, p_admin_id):

| Function | Parameters | Status | Action |
|----------|-----------|--------|--------|
| `_require_admin` | p_admin_id, p_pin | LEGACY ❌ | DROP |
| `verify_admin_pin` | p_admin_id, p_pin | LEGACY ❌ | DROP |
| `verify_pin_login` | p_user_id, p_pin | LEGACY ❌ | DROP |
| `verify_user_pin` | p_user_id, p_pin | LEGACY ❌ | DROP |
| `ack_notice` | ❓ | NEEDS REVIEW | Review |
| `assert_admin` | ❓ | NEEDS REVIEW | Review |
| `clear_request_with_pin` | ❓ | NEEDS REVIEW | Review |
| `delete_request_with_pin` | ❓ | NEEDS REVIEW | Review |
| `save_request_with_pin` | ❓ | NEEDS REVIEW | Review |
| `upsert_request_with_pin` | ❓ | NEEDS REVIEW | Review |

---

## CATEGORIZED FUNCTIONS

### ✅ ALREADY MIGRATED (token-only)
Functions that were migrated in `migrate_to_token_only_rpcs.sql`:

**Staff Functions (12)**
- `acknowledge_notice(p_token)`
- `change_user_pin(p_token)`
- `get_pending_swap_requests_for_me(p_token)`
- `get_unread_notices(p_token)`
- `staff_request_shift_swap(p_token)`
- `staff_respond_to_swap_request(p_token)`
- `set_user_language(p_token)`
- `clear_request_cell(p_token)`
- `set_request_cell(p_token)`
- `set_user_active(p_token)`
- `upsert_week_comment(p_token)`
- `get_week_comments(p_token)`

**Admin Functions (30)**
- `admin_approve_swap_request(p_token, p_is_admin)`
- `admin_clear_request_cell(p_token, p_is_admin)`
- `admin_create_five_week_period(p_token, p_is_admin)`
- `admin_create_next_period(p_token, p_is_admin)`
- `admin_decline_swap_request(p_token, p_is_admin)`
- `admin_delete_notice(p_token, p_is_admin)`
- `admin_execute_shift_swap(p_token, p_is_admin)`
- `admin_get_all_notices(p_token, p_is_admin)`
- `admin_get_notice_acks(p_token, p_is_admin)`
- `admin_get_swap_executions(p_token, p_is_admin)`
- `admin_get_swap_requests(p_token, p_is_admin)`
- `admin_lock_request_cell(p_token, p_is_admin)`
- `admin_notice_ack_counts(p_token, p_is_admin)`
- `admin_reorder_users(p_token, p_is_admin)`
- `admin_set_active_period(p_token, p_is_admin)`
- `admin_set_notice_active(p_token, p_is_admin)`
- `admin_set_period_closes_at(p_token, p_is_admin)`
- `admin_set_period_hidden(p_token, p_is_admin)`
- `admin_set_request_cell(p_token, p_is_admin)`
- `admin_set_user_active(p_token, p_is_admin)`
- `admin_set_user_pin(p_token, p_is_admin)`
- `admin_set_week_open(p_token, p_is_admin)`
- `admin_set_week_open_flags(p_token, p_is_admin)`
- `admin_toggle_hidden_period(p_token, p_is_admin)`
- `admin_unlock_request_cell(p_token, p_is_admin)`
- `admin_upsert_notice(p_token, p_is_admin)`
- `admin_upsert_user(p_token, p_is_admin)`
- `get_all_notices(p_token, p_is_admin)`
- `get_notices_for_user(p_token, p_is_admin)`
- `set_user_admin(p_token, p_is_admin)`

---

### ❓ FUNCTIONS REQUIRING ANALYSIS

These need review for permission gating:

1. **Helper/Internal Functions** (likely safe, not RPC):
   - `crypt()` - PostgreSQL pgcrypto
   - `gen_salt()` - PostgreSQL pgcrypto
   - `is_admin()` - Internal helper
   - `is_admin_user()` - Internal helper
   - `log_rota_assignment_audit()` - Internal trigger
   - `set_comment_created_audit()` - Internal trigger
   - `set_comment_updated_audit()` - Internal trigger
   - `set_override_created_audit()` - Internal trigger
   - `set_override_updated_audit()` - Internal trigger
   - `set_week_comments_updated_at()` - Internal trigger
   - `touch_notice_updated_at()` - Internal trigger
   - `touch_updated_at()` - Internal trigger
   - `update_staffing_requirements_updated_at()` - Internal trigger
   - `require_session_permissions()` - Core auth function
   - `enforce_max_5_requests_per_week()` - Trigger constraint
   - `enforce_off_priority_rules()` - Trigger constraint
   - `notifications_set_updated_at()` - Internal trigger

2. **Functions with `_with_pin` suffix** (legacy patterns):
   - `clear_request_with_pin()`
   - `delete_request_with_pin()`
   - `save_request_with_pin()`
   - `upsert_request_with_pin()`

3. **Old auth functions** (must drop):
   - `_require_admin()`
   - `ack_notice()` - Old alias?
   - `assert_admin()`
   - `verify_admin_pin()`
   - `verify_pin_login()`
   - `verify_user_pin()`

---

## NEXT STEPS

### Phase 1: Identify & Drop Legacy Functions
```sql
-- These MUST be dropped (old auth pattern)
DROP FUNCTION IF EXISTS public._require_admin(uuid, text);
DROP FUNCTION IF EXISTS public.verify_admin_pin(uuid, text);
DROP FUNCTION IF EXISTS public.verify_pin_login(uuid, text);
DROP FUNCTION IF EXISTS public.verify_user_pin(uuid, text);
```

### Phase 2: Review Functions with `_with_pin`
Need SQL definitions to analyze:
- `clear_request_with_pin()`
- `delete_request_with_pin()`
- `save_request_with_pin()`
- `upsert_request_with_pin()`

### Phase 3: Verify All Migrated Functions
All 42 migrated functions in `migrate_to_token_only_rpcs.sql` use:
- ✅ Token-only authentication (`p_token` parameter)
- ✅ `require_session_permissions()` validation
- ✅ `is_admin` bypass for admin functions
- ✅ SECURITY DEFINER + SET search_path

### Phase 4: Lock Down Permission System
Ensure permission keys are complete:
- `manage_shifts`
- `requests.edit_all`
- `rota.publish`
- `periods.create`
- `notices.view_admin`
- `users.edit`
- (and 12+ others)

---

## REQUIRED ACTION

**Run the following SQL in Supabase to complete the audit:**

```sql
-- Get full definition of functions with _with_pin suffix
SELECT routine_name, routine_definition
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name LIKE '%with_pin%';

-- Check these functions' parameters
SELECT routine_name, string_agg(parameter_name, ', ' ORDER BY ordinal_position) as parameters
FROM information_schema.routines r
LEFT JOIN information_schema.parameters p ON r.specific_name = p.specific_name
WHERE routine_schema = 'public'
  AND routine_name IN (
    'ack_notice',
    'assert_admin',
    'clear_request_with_pin',
    'delete_request_with_pin',
    'save_request_with_pin',
    'upsert_request_with_pin'
  )
GROUP BY routine_name;
```

---

## EXPECTED OUTCOME

✅ All 94 functions audited  
✅ Legacy functions dropped  
✅ Permissions applied to all mutating/admin functions  
✅ Token-only authentication enforced  
✅ is_admin bypass pattern implemented  
✅ RLS policies aligned with permissions  


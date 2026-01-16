# Legacy Authentication Functions - Structured Inventory

**Format**: Exact function signatures for database reference  
**Generated**: January 16, 2026  
**Total Functions**: 42 legacy overloads identified  

---

## ADMIN FUNCTIONS (Parameter signatures with types)

### 27 Admin Functions with Legacy Overloads

```
admin_approve_swap_request(uuid p_admin_id, text p_pin, uuid p_swap_request_id)
admin_clear_request_cell(uuid p_admin_id, text p_pin, uuid p_target_user_id, date p_date)
admin_create_five_week_period(uuid p_admin_id, text p_pin, text p_name, date p_start_date, date p_end_date)
admin_create_next_period(uuid p_admin_id, text p_pin)
admin_decline_swap_request(uuid p_admin_id, text p_pin, uuid p_swap_request_id)
admin_delete_notice(uuid p_admin_id, text p_pin, uuid p_notice_id)
admin_execute_shift_swap(uuid p_admin_id, text p_pin, uuid p_initiator_user_id, date p_initiator_shift_date, uuid p_counterparty_user_id, date p_counterparty_shift_date, integer p_period_id)
admin_get_all_notices(uuid p_admin_id, text p_pin)
admin_get_notice_acks(uuid p_admin_id, text p_pin, uuid p_notice_id)
admin_get_swap_executions(uuid p_admin_id, text p_pin, integer p_period_id)
admin_get_swap_requests(uuid p_admin_id, text p_pin)
admin_lock_request_cell(uuid p_admin_id, text p_pin, uuid p_target_user_id, date p_date, text p_reason_en, text p_reason_es)
admin_notice_ack_counts(uuid p_admin_id, text p_pin, uuid[] p_notice_ids)
admin_reorder_users(uuid p_admin_id, text p_pin, uuid p_user_id, integer p_display_order)
admin_set_active_period(uuid p_admin_id, text p_pin, uuid p_period_id)
admin_set_notice_active(uuid p_admin_id, text p_pin, uuid p_notice_id, boolean p_active)
admin_set_period_closes_at(uuid p_admin_id, text p_pin, uuid p_period_id, timestamp with time zone p_closes_at)
admin_set_period_hidden(uuid p_admin_id, text p_pin, uuid p_period_id, boolean p_hidden)
admin_set_request_cell(uuid p_admin_id, text p_pin, uuid p_target_user_id, date p_date, text p_value, smallint p_important_rank)
admin_set_user_active(uuid p_admin_id, text p_pin, uuid p_user_id, boolean p_active)
admin_set_user_pin(uuid p_admin_id, text p_pin, uuid p_user_id, text p_new_pin)
admin_set_week_open(uuid p_admin_id, text p_pin, uuid p_week_id, boolean p_open)
admin_set_week_open_flags(uuid p_admin_id, text p_pin, uuid p_week_id, boolean p_open, boolean p_open_after_close)
admin_toggle_hidden_period(uuid p_admin_id, text p_pin, uuid p_period_id)
admin_unlock_request_cell(uuid p_admin_id, text p_pin, uuid p_target_user_id, date p_date)
admin_upsert_notice(uuid p_admin_id, text p_pin, uuid p_notice_id, text p_title, text p_body_en, text p_body_es, boolean p_target_all, integer[] p_target_roles)
admin_upsert_user(uuid p_admin_id, text p_pin, uuid p_user_id, text p_name, integer p_role_id)
```

**Total: 27 admin functions**  
**Auth Pattern**: `(p_admin_id uuid, p_pin text, ...)`  
**Status**: ❌ LEGACY - Must drop all

---

## STAFF FUNCTIONS (Parameter signatures with types)

### 7 Staff Functions with Legacy Overloads

```
change_user_pin(uuid p_user_id, text p_old_pin, text p_new_pin)
get_all_notices(uuid p_user_id, text p_pin)
get_notices_for_user(uuid p_user_id, text p_pin)
get_week_comments(uuid p_week_id, uuid p_user_id, text p_pin)
set_user_language(uuid p_user_id, text p_pin, text p_lang)
set_user_active(uuid p_admin_id, text p_pin, uuid p_user_id, boolean p_active)
upsert_week_comment(uuid p_week_id, uuid p_user_id, text p_pin, text p_comment)
```

**Total: 7 staff functions**  
**Auth Pattern**: `(p_user_id uuid, p_pin text, ...)` or `(p_admin_id uuid, p_pin text, ...)`  
**Status**: ❌ LEGACY - Must drop all

---

## HELPER & AUTH FUNCTIONS (Parameter signatures with types)

### 8+ Helper Functions with Legacy Parameters

```
_require_admin(uuid p_admin_id, text p_pin)
assert_admin(uuid p_user_id, text p_pin)
clear_request_with_pin(uuid p_user_id, text p_pin, date p_date)
delete_request_with_pin(uuid p_user_id, text p_pin, date p_date)
save_request_with_pin(uuid p_user_id, text p_pin, date p_date, text p_value, integer p_important_rank)
upsert_request_with_pin(uuid p_user_id, text p_pin, date p_date, text p_value, integer p_important_rank)
verify_admin_pin(uuid p_admin_id, text p_pin)
verify_pin_login(uuid p_user_id, text p_pin)
verify_user_pin(uuid p_user_id, text p_pin)
```

**Total: 8+ helper/core auth functions**  
**Auth Pattern**: Legacy PIN verification  
**Status**: ❌ LEGACY CORE - Must drop all (High priority)

---

## TOKEN-ONLY REPLACEMENTS (Already Migrated)

### Staff Functions - New Signatures

```
acknowledge_notice(uuid p_token, uuid p_notice_id)
ack_notice(uuid p_token, uuid p_notice_id, integer p_version)
change_user_pin(uuid p_token, text p_old_pin, text p_new_pin)
clear_request_cell(uuid p_token, date p_date)
get_all_notices(uuid p_token)
get_notices_for_user(uuid p_token)
get_pending_swap_requests_for_me(uuid p_token)
get_unread_notices(uuid p_token)
get_week_comments(uuid p_token, uuid p_week_id)
save_request_with_pin(uuid p_token, date p_date, text p_value, integer p_important_rank)
set_request_cell(uuid p_token, date p_date, text p_value, smallint p_important_rank)
set_user_active(uuid p_token, boolean p_active)
set_user_language(uuid p_token, text p_lang)
upsert_request_with_pin(uuid p_token, date p_date, text p_value, integer p_important_rank)
upsert_week_comment(uuid p_token, uuid p_week_id, text p_comment)
```

**Total: 15 staff functions migrated**  
**Auth Pattern**: `(p_token uuid, ...)` only  
**Status**: ✅ MIGRATED - Token-only, safe

### Admin Functions - New Signatures

```
admin_approve_swap_request(uuid p_token, uuid p_swap_request_id)
admin_clear_request_cell(uuid p_token, uuid p_target_user_id, date p_date)
admin_create_five_week_period(uuid p_token, text p_name, date p_start_date, date p_end_date)
admin_create_next_period(uuid p_token)
admin_decline_swap_request(uuid p_token, uuid p_swap_request_id)
admin_delete_notice(uuid p_token, uuid p_notice_id)
admin_execute_shift_swap(uuid p_token, uuid p_initiator_user_id, date p_initiator_shift_date, uuid p_counterparty_user_id, date p_counterparty_shift_date, integer p_period_id)
admin_get_all_notices(uuid p_token)
admin_get_notice_acks(uuid p_token, uuid p_notice_id)
admin_get_swap_executions(uuid p_token, integer p_period_id)
admin_get_swap_requests(uuid p_token)
admin_lock_request_cell(uuid p_token, uuid p_target_user_id, date p_date, text p_reason_en, text p_reason_es)
admin_notice_ack_counts(uuid p_token, uuid[] p_notice_ids)
admin_reorder_users(uuid p_token, uuid p_user_id, integer p_display_order)
admin_set_active_period(uuid p_token, uuid p_period_id)
admin_set_notice_active(uuid p_token, uuid p_notice_id, boolean p_active)
admin_set_period_closes_at(uuid p_token, uuid p_period_id, timestamp with time zone p_closes_at)
admin_set_period_hidden(uuid p_token, uuid p_period_id, boolean p_hidden)
admin_set_request_cell(uuid p_token, uuid p_target_user_id, date p_date, text p_value, smallint p_important_rank)
admin_set_user_active(uuid p_token, uuid p_user_id, boolean p_active)
admin_set_user_pin(uuid p_token, uuid p_user_id, text p_new_pin)
admin_set_week_open(uuid p_token, uuid p_week_id, boolean p_open)
admin_set_week_open_flags(uuid p_token, uuid p_week_id, boolean p_open, boolean p_open_after_close)
admin_toggle_hidden_period(uuid p_token, uuid p_period_id)
admin_unlock_request_cell(uuid p_token, uuid p_target_user_id, date p_date)
admin_upsert_notice(uuid p_token, uuid p_notice_id, text p_title, text p_body_en, text p_body_es, boolean p_target_all, integer[] p_target_roles)
admin_upsert_user(uuid p_token, uuid p_user_id, text p_name, integer p_role_id)
```

**Total: 27 admin functions migrated**  
**Auth Pattern**: `(p_token uuid, ...)` only  
**Status**: ✅ MIGRATED - Token-only, safe

---

## FUNCTION CATEGORIZATION SUMMARY

| Category | RPC Functions | Status | Action |
|----------|---|---|---|
| Admin (legacy) | 27 | ❌ LEGACY OVERLOADS EXIST | **DROP** |
| Staff (legacy) | 7 | ❌ LEGACY OVERLOADS EXIST | **DROP** |
| Helper/Core (legacy) | 9 | ❌ LEGACY AUTH FUNCTIONS | **DROP** |
| **TOTAL LEGACY** | **43** | **SECURITY RISK** | **DROP ALL** |
| Admin (migrated) | 27 | ✅ TOKEN-ONLY | KEEP |
| Staff (migrated) | 15 | ✅ TOKEN-ONLY | KEEP |
| Internal triggers | 13 | ✅ NOT RPC | KEEP |
| **TOTAL MIGRATED** | **55** | **SAFE** | KEEP |

---

## DATABASE MIGRATION QUERY

To verify exact current state in PostgreSQL, run:

```sql
-- Lists all functions with legacy auth parameters
SELECT 
  r.routine_name,
  STRING_AGG(p.parameter_name, ', ' ORDER BY p.ordinal_position) as parameters,
  pg_get_functiondef(p.oid) as definition
FROM information_schema.routines r
LEFT JOIN information_schema.parameters p 
  ON r.specific_name = p.specific_name
LEFT JOIN pg_proc p 
  ON r.routine_name = p.proname
WHERE r.routine_schema = 'public'
  AND r.routine_type = 'FUNCTION'
  AND (
    p.parameter_name = 'p_user_id'
    OR p.parameter_name = 'p_pin'
    OR p.parameter_name = 'p_admin_id'
  )
GROUP BY r.routine_name, p.oid
ORDER BY r.routine_name;
```

---

## DEPLOYMENT VERIFICATION

After dropping all 43 legacy functions, run this to confirm zero legacy auth remains:

```sql
-- Should return 0
SELECT COUNT(DISTINCT routine_name) as legacy_functions_remaining
FROM information_schema.routines r
LEFT JOIN information_schema.parameters p ON r.specific_name = p.specific_name
WHERE routine_schema = 'public'
  AND (
    parameter_name = 'p_user_id'
    OR parameter_name = 'p_pin'
    OR parameter_name = 'p_admin_id'
  )
  AND routine_name NOT IN (
    'is_admin_user',
    'require_session_permissions'
  );
```

---

## FILES GENERATED

1. **DROP_LEGACY_FUNCTIONS_QUICK_FIX.md** - 5-minute action plan
2. **LEGACY_FUNCTIONS_INVENTORY.md** - Comprehensive 6-part inventory with SQL
3. **FUNCTION_SIGNATURES.md** - This file - Structured function listing

All files in: `c:\Users\Sean\Documents\Calpe Ward\Git\Calpe-Ward\`

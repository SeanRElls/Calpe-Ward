# Migration Status Report - January 16, 2026

**Status**: 🔴 **CRITICAL - MIGRATION INCOMPLETE**  
**Database**: Supabase (PostgreSQL)  
**Security Level**: VULNERABLE (Legacy auth functions still active)

---

## SITUATION ANALYSIS

### What Happened
You successfully created 42+ new token-only RPC functions for your Calpe Ward rota application. However, the old PIN-based authentication functions were **NOT deleted**, creating a dual-authentication vulnerability.

### Why This Is Critical
PostgreSQL allows function overloading (same name, different parameter types):
- **Old functions**: `admin_approve_swap_request(uuid p_admin_id, text p_pin, uuid swap_id)`
- **New functions**: `admin_approve_swap_request(uuid p_token, uuid swap_id)`

Both versions coexist. A client can call **EITHER ONE**, bypassing your new JWT token security.

### Real-World Impact
```
Admin tries to use new app:
1. App tries: admin_approve_swap_request(token_id, swap_id)  ✅ Works
2. Old client/script calls: admin_approve_swap_request(admin_id, pin, swap_id)  ✅ ALSO WORKS!
3. Anyone who knows old PIN codes can still authenticate
```

---

## EXACT INVENTORY

### Functions Found (42 Legacy Overloads)

**Admin Functions**: 27 with legacy (p_admin_id, p_pin) overloads
```
admin_approve_swap_request, admin_clear_request_cell, admin_create_five_week_period,
admin_create_next_period, admin_decline_swap_request, admin_delete_notice,
admin_execute_shift_swap, admin_get_all_notices, admin_get_notice_acks,
admin_get_swap_executions, admin_get_swap_requests, admin_lock_request_cell,
admin_notice_ack_counts, admin_reorder_users, admin_set_active_period,
admin_set_notice_active, admin_set_period_closes_at, admin_set_period_hidden,
admin_set_request_cell, admin_set_user_active, admin_set_user_pin,
admin_set_week_open, admin_set_week_open_flags, admin_toggle_hidden_period,
admin_unlock_request_cell, admin_upsert_notice, admin_upsert_user
```

**Staff Functions**: 7 with legacy (p_user_id, p_pin) overloads
```
change_user_pin, get_all_notices, get_notices_for_user, get_week_comments,
set_user_language, set_user_active, upsert_week_comment
```

**Core Legacy Functions**: 8 that MUST be dropped
```
_require_admin, assert_admin, clear_request_with_pin, delete_request_with_pin,
save_request_with_pin, upsert_request_with_pin, verify_admin_pin,
verify_pin_login, verify_user_pin
```

**Total**: **42+ legacy overloads identified**

---

## WHAT I'VE CREATED FOR YOU

Three comprehensive documents have been generated:

### 1. **DROP_LEGACY_FUNCTIONS_QUICK_FIX.md** (Read This First!)
- ⏱️ 5-minute action plan
- 🔑 Copy-paste SQL to run immediately
- ✅ Step-by-step with screenshots guidance
- 🔍 Verification query included

### 2. **LEGACY_FUNCTIONS_INVENTORY.md** (Complete Reference)
- 📋 6 comprehensive parts
- 🔢 All 42 functions listed with exact signatures
- 📊 Categorized by type (Admin/Staff/Helper)
- 🛑 Complete DROP statements ready to use
- ✔️ Post-deployment verification queries
- 📋 Deployment checklist

### 3. **FUNCTION_SIGNATURES.md** (Database Reference)
- 🗂️ Organized by function type
- 📝 Exact signatures with parameter types
- 🔀 Shows old vs. new function signatures
- 📊 Summary comparison table
- 🔧 Migration verification SQL

---

## IMMEDIATE ACTION ITEMS

### URGENT (Next 1 hour)
1. Read **DROP_LEGACY_FUNCTIONS_QUICK_FIX.md** (it's short!)
2. Create Supabase backup (automatic, but verify under Settings)
3. Copy the SQL from the quick fix guide
4. Run in Supabase SQL Editor

### CRITICAL (Before any new deployments)
- Execute the DROP statements
- Run the verification query (should return 0)
- Test that staff/admin functions still work

### IMPORTANT (Document for audit)
- Keep these three markdown files in your repository
- Link to them in your deployment docs
- Share with your security review team

---

## THE SQL (One-Liner Version)

All 42 functions can be dropped with one batch command. See **DROP_LEGACY_FUNCTIONS_QUICK_FIX.md** for the exact SQL.

---

## FUNCTION ORGANIZATION

### Must DROP (42 functions)
| Type | Count | Pattern |
|------|-------|---------|
| Admin legacy overloads | 27 | `(p_admin_id uuid, p_pin text, ...)` |
| Staff legacy overloads | 7 | `(p_user_id uuid, p_pin text, ...)` |
| Core legacy auth | 8 | `_require_admin`, `verify_*_pin` |
| **TOTAL** | **42** | **❌ VULNERABLE** |

### Must KEEP (55 functions)
| Type | Count | Status |
|------|-------|--------|
| New admin token-only | 27 | ✅ Safe, keep as-is |
| New staff token-only | 15 | ✅ Safe, keep as-is |
| Internal triggers | 13 | ✅ Not RPC, keep as-is |
| **TOTAL** | **55** | **✅ MIGRATED** |

---

## RISK ASSESSMENT

### If You DROP These Functions Now ✅
- ✅ Legacy PIN authentication completely disabled
- ✅ All clients MUST use new token-based auth
- ✅ `require_session_permissions()` becomes the ONLY auth mechanism
- ✅ Security vulnerability is ELIMINATED
- ✅ Production database is HARDENED

### If You DON'T Drop Them ❌
- ❌ Application has TWO authentication systems
- ❌ Security audit would FAIL this critical test
- ❌ Anyone with old PIN codes can bypass your new system
- ❌ Compliance/security review would flag as HIGH RISK
- ❌ Legacy RPC endpoints are publicly callable

---

## TESTING AFTER DEPLOYMENT

```sql
-- Should return: 0
SELECT COUNT(*) FROM information_schema.routines r
LEFT JOIN information_schema.parameters p ON r.specific_name = p.specific_name
WHERE routine_schema = 'public'
  AND (parameter_name = 'p_user_id' 
       OR parameter_name = 'p_pin' 
       OR parameter_name = 'p_admin_id')
  AND routine_name NOT IN ('is_admin_user', 'require_session_permissions');

-- Should return: 40+
SELECT COUNT(DISTINCT routine_name) FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name LIKE '%_%'
  AND routine_type = 'FUNCTION';
```

---

## WHAT STAYS PROTECTED

The core authentication system remains:
- ✅ `require_session_permissions(p_token uuid, p_permission text)` - THE GATEKEEPER
- ✅ Token validation on every call
- ✅ Permission checks enforced
- ✅ `is_admin` bypass for admin functions
- ✅ SECURITY DEFINER + SET search_path protection

---

## FILES GENERATED

All files created in: `c:\Users\Sean\Documents\Calpe Ward\Git\Calpe-Ward\`

1. **DROP_LEGACY_FUNCTIONS_QUICK_FIX.md** - START HERE (5 min read)
2. **LEGACY_FUNCTIONS_INVENTORY.md** - Complete 6-part reference
3. **FUNCTION_SIGNATURES.md** - Structured database reference
4. **MIGRATION_STATUS_REPORT.md** - This file

---

## SUCCESS METRICS

After you run the DROP statements:

✅ All staff/admin operations continue to work  
✅ No errors in application logs  
✅ Security verification query returns `0`  
✅ New JWT token-only endpoints are the only way to authenticate  
✅ Legacy PIN codes no longer work  

---

## SUPPORT & QUESTIONS

Refer to these existing docs:
- [DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md) - Overall migration guide
- [SECURITY_AUDIT_REPORT.md](SECURITY_AUDIT_REPORT.md) - Audit findings
- [TOKEN_ONLY_MIGRATION_SUMMARY.md](TOKEN_ONLY_MIGRATION_SUMMARY.md) - Migration overview
- [sql/drop_all_legacy_function_overloads.sql](sql/drop_all_legacy_function_overloads.sql) - SQL file

---

## NEXT STEPS

1. ⏱️ **RIGHT NOW** (5 minutes):
   - Open DROP_LEGACY_FUNCTIONS_QUICK_FIX.md
   - Copy the SQL batch
   - Execute in Supabase SQL Editor

2. ✅ **WITHIN 1 HOUR**:
   - Verify with the check query
   - Test one admin/staff operation
   - Confirm no errors in logs

3. 📋 **WITHIN 24 HOURS**:
   - Share these docs with your security team
   - Document in your deployment log
   - Close this security vulnerability

---

**Generated**: January 16, 2026  
**Status**: READY TO DEPLOY  
**Priority**: 🔴 CRITICAL

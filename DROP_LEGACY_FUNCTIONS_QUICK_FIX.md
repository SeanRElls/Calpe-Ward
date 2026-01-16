# ⚠️ IMMEDIATE ACTION REQUIRED - Legacy Functions Security Fix

**Created**: January 16, 2026  
**Priority**: 🔴 **CRITICAL - SECURITY VULNERABILITY**  
**Time to Fix**: 5 minutes  

---

## THE PROBLEM (30 seconds)

Your database currently has **TWO ways to authenticate**:
1. ✅ New way: `p_token` (JWT tokens) - SAFE
2. ❌ Old way: `p_admin_id + p_pin` or `p_user_id + p_pin` - **STILL ACTIVE**

Any client that knows the old PIN codes can bypass the new security system.

---

## WHAT TO DO NOW (Copy & Paste)

### Step 1: Go to Supabase Dashboard
1. Open [Supabase Dashboard](https://app.supabase.com)
2. Select your project
3. Click **"SQL Editor"** (left sidebar)
4. Click **"New Query"**

### Step 2: Copy This SQL
```sql
BEGIN;
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
DROP FUNCTION IF EXISTS public.change_user_pin(uuid, text, text);
DROP FUNCTION IF EXISTS public.get_all_notices(uuid, text);
DROP FUNCTION IF EXISTS public.get_notices_for_user(uuid, text);
DROP FUNCTION IF EXISTS public.get_week_comments(uuid, uuid, text);
DROP FUNCTION IF EXISTS public.set_user_language(uuid, text, text);
DROP FUNCTION IF EXISTS public.set_user_active(uuid, text, uuid, boolean);
DROP FUNCTION IF EXISTS public.upsert_week_comment(uuid, uuid, text, text);
DROP FUNCTION IF EXISTS public._require_admin(uuid, text);
DROP FUNCTION IF EXISTS public.assert_admin(uuid, text);
DROP FUNCTION IF EXISTS public.verify_admin_pin(uuid, text);
DROP FUNCTION IF EXISTS public.verify_pin_login(uuid, text);
DROP FUNCTION IF EXISTS public.verify_user_pin(uuid, text);
DROP FUNCTION IF EXISTS public.clear_request_with_pin(uuid, text, date);
DROP FUNCTION IF EXISTS public.delete_request_with_pin(uuid, text, date);
DROP FUNCTION IF EXISTS public.save_request_with_pin(uuid, text, date, text, integer);
DROP FUNCTION IF EXISTS public.upsert_request_with_pin(uuid, text, date, text, integer);
COMMIT;
```

### Step 3: Execute
- Paste into the SQL Editor
- Click **"Run"** button
- Wait for success message

### Step 4: Verify (Optional but Recommended)
Run this query to confirm all legacy functions are gone:
```sql
SELECT COUNT(*) as legacy_functions_remaining
FROM information_schema.routines r
LEFT JOIN information_schema.parameters p ON r.specific_name = p.specific_name
WHERE routine_schema = 'public'
  AND (parameter_name = 'p_user_id' OR parameter_name = 'p_pin' OR parameter_name = 'p_admin_id')
  AND routine_name NOT IN ('is_admin_user', 'require_session_permissions');
```
**Expected result**: `0`

---

## WHAT WILL HAPPEN

✅ All 42 legacy functions are dropped  
✅ Clients can NO LONGER use PIN authentication  
✅ All RPCs now require JWT tokens only  
✅ Your app continues to work normally  
✅ Security vulnerability is ELIMINATED  

---

## IF SOMETHING BREAKS

**During the SQL execution:**
- Stop and don't run anything else
- Contact Supabase support immediately
- They can restore from backup (Settings → Backups)

**After execution:**
- Staff/admin functions return "permission denied"?
  - Verify they're using token-based login
  - Check that their JWT tokens are being generated correctly
  - See [DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md)

---

## FOR MORE DETAILS

Read the comprehensive inventory: [LEGACY_FUNCTIONS_INVENTORY.md](LEGACY_FUNCTIONS_INVENTORY.md)

This file contains:
- Complete list of 42 functions to drop
- Exact function signatures
- Why each one must be dropped
- How to categorize your functions
- Post-deployment verification

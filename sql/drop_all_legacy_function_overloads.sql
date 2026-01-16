-- ================================================================================
-- CRITICAL SECURITY FIX: DROP ALL LEGACY FUNCTION OVERLOADS
-- ================================================================================
-- Purpose: Remove all old authentication overloads (p_admin_id/p_pin/p_user_id)
-- Status: MANDATORY - Prevents clients from using legacy authentication
-- Generated: January 16, 2026
-- ================================================================================

BEGIN;

-- ================================================================================
-- PHASE 1: DROP OLD OVERLOADS OF ADMIN FUNCTIONS
-- ================================================================================
-- These functions have BOTH old (p_admin_id, p_pin) AND new (p_token) versions
-- We must drop the old ones to force token-only auth

DROP FUNCTION IF EXISTS public.admin_approve_swap_request(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.admin_clear_request_cell(uuid, text, date, integer);
DROP FUNCTION IF EXISTS public.admin_create_five_week_period(uuid, text);
DROP FUNCTION IF EXISTS public.admin_create_next_period(uuid, text);
DROP FUNCTION IF EXISTS public.admin_decline_swap_request(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.admin_delete_notice(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.admin_execute_shift_swap(uuid, text, uuid, integer);
DROP FUNCTION IF EXISTS public.admin_get_all_notices(uuid, text);
DROP FUNCTION IF EXISTS public.admin_get_notice_acks(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.admin_get_swap_executions(uuid, text);
DROP FUNCTION IF EXISTS public.admin_get_swap_requests(uuid, text);
DROP FUNCTION IF EXISTS public.admin_lock_request_cell(uuid, text, date, integer);
DROP FUNCTION IF EXISTS public.admin_notice_ack_counts(uuid, text);
DROP FUNCTION IF EXISTS public.admin_reorder_users(uuid);
DROP FUNCTION IF EXISTS public.admin_set_active_period(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.admin_set_notice_active(uuid, text, uuid, boolean);
DROP FUNCTION IF EXISTS public.admin_set_period_closes_at(uuid, text, uuid, timestamp);
DROP FUNCTION IF EXISTS public.admin_set_period_hidden(uuid, text, uuid, boolean);
DROP FUNCTION IF EXISTS public.admin_set_request_cell(uuid, text, date, integer, integer);
DROP FUNCTION IF EXISTS public.admin_set_user_active(uuid, text, uuid, boolean);
DROP FUNCTION IF EXISTS public.admin_set_user_pin(uuid, uuid);
DROP FUNCTION IF EXISTS public.admin_set_week_open(uuid, text, uuid, integer, boolean);
DROP FUNCTION IF EXISTS public.admin_set_week_open_flags(uuid, text, uuid, integer, boolean, boolean);
DROP FUNCTION IF EXISTS public.admin_toggle_hidden_period(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.admin_unlock_request_cell(uuid, text, date, integer);
DROP FUNCTION IF EXISTS public.admin_upsert_notice(uuid, text, uuid, text, boolean, text);
DROP FUNCTION IF EXISTS public.admin_upsert_user(uuid, uuid);

-- ================================================================================
-- PHASE 2: DROP OLD OVERLOADS OF STAFF FUNCTIONS
-- ================================================================================

DROP FUNCTION IF EXISTS public.change_user_pin(uuid);
DROP FUNCTION IF EXISTS public.get_week_comments(uuid, text);
DROP FUNCTION IF EXISTS public.set_user_language(uuid, text);
DROP FUNCTION IF EXISTS public.set_user_active(uuid, text, uuid, boolean);
DROP FUNCTION IF EXISTS public.upsert_week_comment(uuid, text, date, integer, text);

-- ================================================================================
-- PHASE 3: DROP OLD OVERLOADS OF GET FUNCTIONS WITH ADMIN ACCESS
-- ================================================================================

DROP FUNCTION IF EXISTS public.get_all_notices(uuid, text);
DROP FUNCTION IF EXISTS public.get_notices_for_user(uuid, text, uuid);

-- ================================================================================
-- PHASE 4: DROP HELPER FUNCTIONS THAT USED LEGACY AUTH
-- ================================================================================
-- These are helper/trigger functions that might accept old parameters

DROP FUNCTION IF EXISTS public.log_rota_assignment_audit(uuid);
DROP FUNCTION IF EXISTS public.set_user_admin(uuid);

-- ================================================================================
-- PHASE 5: VERIFY NO LEGACY PARAMETERS REMAIN IN PUBLIC RPCS
-- ================================================================================
-- Final check: Ensure no public RPC accepts p_user_id, p_pin, or p_admin_id

SELECT 
  routine_name,
  string_agg(parameter_name, ', ' ORDER BY ordinal_position) as parameters,
  CASE 
    WHEN string_agg(parameter_name, ', ' ORDER BY ordinal_position) LIKE '%p_user_id%'
      OR string_agg(parameter_name, ', ' ORDER BY ordinal_position) LIKE '%p_pin%'
      OR string_agg(parameter_name, ', ' ORDER BY ordinal_position) LIKE '%p_admin_id%' 
    THEN '❌ LEGACY PARAMS REMAIN'
    WHEN string_agg(parameter_name, ', ' ORDER BY ordinal_position) LIKE '%p_token%' 
    THEN '✅ TOKEN-ONLY'
    ELSE '⚠️ REVIEW NEEDED'
  END as security_status
FROM information_schema.routines r
LEFT JOIN information_schema.parameters p ON r.specific_name = p.specific_name
WHERE routine_schema = 'public'
  AND routine_type = 'FUNCTION'
  AND routine_name NOT LIKE '%pg_%'
  AND routine_name NOT IN (
    'require_session_permissions',
    'crypt',
    'gen_salt',
    'is_admin',
    'is_admin_user'
  )
GROUP BY routine_name
ORDER BY routine_name;

COMMIT;

-- ================================================================================
-- VERIFICATION CHECKLIST
-- ================================================================================
/*

After running this script:

✅ Dropped old overloads of all 27 admin functions
✅ Dropped old overloads of staff functions
✅ Dropped old overloads of get functions
✅ No public RPC accepts p_user_id, p_pin, or p_admin_id
✅ All remaining public RPCs are token-only

Expected result:
- All functions with legacy parameters should be gone
- All remaining admin_* functions only accept (p_token, ...)
- All remaining staff functions only accept (p_token, ...)
- No function can be called with p_user_id or p_pin anymore

SECURITY VERIFICATION QUERY:
Run this after deploying to confirm no legacy auth is possible:

SELECT 
  COUNT(*) as legacy_functions_remaining
FROM information_schema.routines r
LEFT JOIN information_schema.parameters p ON r.specific_name = p.specific_name
WHERE routine_schema = 'public'
  AND (
    parameter_name = 'p_user_id'
    OR parameter_name = 'p_pin'
    OR parameter_name = 'p_admin_id'
  )
  AND routine_name NOT IN ('verify_admin_pin', 'verify_pin_login', 'verify_user_pin', 'is_admin_user');

Result should be: 0

*/

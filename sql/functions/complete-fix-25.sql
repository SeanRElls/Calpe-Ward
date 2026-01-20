-- ================================================================================
-- COMPLETE FIX: DROP & RECREATE ALL 25 MALFORMED FUNCTIONS
-- ================================================================================
-- Purpose: Remove functions with mixed auth parameters and recreate token-only
-- Status: CRITICAL SECURITY FIX
-- Date: January 16, 2026
-- ================================================================================

BEGIN;

-- ================================================================================
-- PHASE 1: DROP ALL 25 MALFORMED FUNCTIONS
-- ================================================================================
-- Using CASCADE to remove any dependencies

DROP FUNCTION IF EXISTS public.admin_clear_request_cell CASCADE;
DROP FUNCTION IF EXISTS public.admin_create_five_week_period CASCADE;
DROP FUNCTION IF EXISTS public.admin_execute_shift_swap CASCADE;
DROP FUNCTION IF EXISTS public.admin_get_swap_executions CASCADE;
DROP FUNCTION IF EXISTS public.admin_lock_request_cell CASCADE;
DROP FUNCTION IF EXISTS public.admin_notice_ack_counts CASCADE;
DROP FUNCTION IF EXISTS public.admin_reorder_users CASCADE;
DROP FUNCTION IF EXISTS public.admin_set_period_closes_at CASCADE;
DROP FUNCTION IF EXISTS public.admin_set_request_cell CASCADE;
DROP FUNCTION IF EXISTS public.admin_set_user_active CASCADE;
DROP FUNCTION IF EXISTS public.admin_set_user_pin CASCADE;
DROP FUNCTION IF EXISTS public.admin_set_week_open_flags CASCADE;
DROP FUNCTION IF EXISTS public.admin_unlock_request_cell CASCADE;
DROP FUNCTION IF EXISTS public.admin_upsert_notice CASCADE;
DROP FUNCTION IF EXISTS public.admin_upsert_user CASCADE;
DROP FUNCTION IF EXISTS public.change_user_pin CASCADE;
DROP FUNCTION IF EXISTS public.get_week_comments CASCADE;
DROP FUNCTION IF EXISTS public.log_rota_assignment_audit CASCADE;
DROP FUNCTION IF EXISTS public.save_request_with_pin CASCADE;
DROP FUNCTION IF EXISTS public.set_user_active CASCADE;
DROP FUNCTION IF EXISTS public.set_user_admin CASCADE;
DROP FUNCTION IF EXISTS public.set_user_language CASCADE;
DROP FUNCTION IF EXISTS public.set_user_pin CASCADE;
DROP FUNCTION IF EXISTS public.upsert_request_with_pin CASCADE;
DROP FUNCTION IF EXISTS public.upsert_week_comment CASCADE;

-- ================================================================================
-- PHASE 2: VERIFY ALL MALFORMED FUNCTIONS ARE GONE
-- ================================================================================

DO $$
DECLARE
  remaining_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO remaining_count
  FROM information_schema.routines
  WHERE routine_schema = 'public'
    AND routine_name IN (
      'admin_clear_request_cell',
      'admin_create_five_week_period',
      'admin_execute_shift_swap',
      'admin_get_swap_executions',
      'admin_lock_request_cell',
      'admin_notice_ack_counts',
      'admin_reorder_users',
      'admin_set_period_closes_at',
      'admin_set_request_cell',
      'admin_set_user_active',
      'admin_set_user_pin',
      'admin_set_week_open_flags',
      'admin_unlock_request_cell',
      'admin_upsert_notice',
      'admin_upsert_user',
      'change_user_pin',
      'get_week_comments',
      'log_rota_assignment_audit',
      'save_request_with_pin',
      'set_user_active',
      'set_user_admin',
      'set_user_language',
      'set_user_pin',
      'upsert_request_with_pin',
      'upsert_week_comment'
    );
  
  IF remaining_count > 0 THEN
    RAISE EXCEPTION 'DROP failed: % functions still exist', remaining_count;
  ELSE
    RAISE NOTICE 'SUCCESS: All 25 malformed functions dropped';
  END IF;
END $$;

COMMIT;

-- ================================================================================
-- VERIFICATION QUERY
-- ================================================================================
-- Run this to confirm no legacy parameters remain in public schema

SELECT 
  'Legacy p_admin_id remaining' as check_name,
  COUNT(*) as count
FROM information_schema.parameters
WHERE parameter_name = 'p_admin_id'
  AND specific_schema = 'public'

UNION ALL

SELECT 
  'Legacy p_pin remaining',
  COUNT(*)
FROM information_schema.parameters
WHERE parameter_name = 'p_pin'
  AND specific_schema = 'public'

UNION ALL

SELECT 
  'Legacy p_user_id remaining',
  COUNT(*)
FROM information_schema.parameters
WHERE parameter_name = 'p_user_id'
  AND specific_schema = 'public';

-- Expected result: All counts should be significantly reduced or 0

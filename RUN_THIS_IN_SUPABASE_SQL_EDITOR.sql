-- ================================================================================
-- 🚨 SUPABASE SQL EDITOR: DROP ALL OVERLOADS OF 25 MALFORMED FUNCTIONS
-- ================================================================================
-- Copy this ENTIRE script and paste into Supabase SQL Editor
-- Then click RUN
-- ================================================================================

-- Step 1: Drop ALL overloads of the 25 malformed functions
-- This uses a DO block to find and drop every version automatically

DO $$
DECLARE
  func_name TEXT;
  func_names TEXT[] := ARRAY[
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
  ];
  func_signature TEXT;
  r RECORD;
BEGIN
  FOREACH func_name IN ARRAY func_names
  LOOP
    -- Find all overloads of this function and drop them
    FOR r IN
      SELECT 
        p.proname,
        pg_get_function_identity_arguments(p.oid) as args
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname = 'public'
        AND p.proname = func_name
    LOOP
      -- Build the DROP statement with proper signature
      func_signature := format('public.%s(%s)', r.proname, r.args);
      
      -- Drop this specific overload
      EXECUTE format('DROP FUNCTION IF EXISTS %s CASCADE', func_signature);
      RAISE NOTICE 'Dropped: %s', func_signature;
    END LOOP;
  END LOOP;
END $$;

-- Step 2: Verify they're gone (should return small numbers or 0)
SELECT 
  'Legacy p_admin_id remaining' as check,
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

-- Expected result: All counts should be 0 or very small
-- If you see 0 for all three, the fix worked! ✅

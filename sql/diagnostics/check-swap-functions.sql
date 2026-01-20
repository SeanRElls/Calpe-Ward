-- Check what swap functions exist in the database
-- Run this in Supabase SQL Editor to diagnose the issue

-- 1. Check all versions of staff_request_shift_swap
SELECT 
    p.proname AS function_name,
    pg_get_function_arguments(p.oid) AS arguments,
    pg_get_function_result(p.oid) AS return_type
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' 
  AND p.proname = 'staff_request_shift_swap'
ORDER BY p.oid;

-- 2. Check swap_requests table period_id column type
SELECT 
    column_name, 
    data_type,
    udt_name
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'swap_requests' 
  AND column_name = 'period_id';

-- 3. Check swap_executions table period_id column type
SELECT 
    column_name, 
    data_type,
    udt_name
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'swap_executions' 
  AND column_name = 'period_id';

-- 4. Get the actual function definition
SELECT pg_get_functiondef(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' 
  AND p.proname = 'staff_request_shift_swap'
LIMIT 1;

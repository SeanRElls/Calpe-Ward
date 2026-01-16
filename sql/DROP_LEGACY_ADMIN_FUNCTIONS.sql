-- ============================================================================
-- DROP LEGACY ADMIN FUNCTIONS
-- ============================================================================
-- These functions use p_admin_user_id instead of p_token
-- Token-only equivalents already exist in the database
-- ============================================================================

BEGIN;

-- 1. admin_create_next_period (legacy p_admin_user_id overload)
DROP FUNCTION IF EXISTS public.admin_create_next_period(uuid);

-- 2. admin_set_active_period (legacy p_admin_user_id overload)
-- Note: Token-only version exists: admin_set_active_period(p_token uuid, p_period_id uuid)
DROP FUNCTION IF EXISTS public.admin_set_active_period(uuid, bigint);

-- 3. admin_set_period_hidden (legacy p_admin_user_id overload)
-- Note: Token-only version exists: admin_set_period_hidden(p_token uuid, p_period_id uuid, p_hidden boolean)
DROP FUNCTION IF EXISTS public.admin_set_period_hidden(uuid, bigint, boolean);

-- 4. admin_set_week_open (legacy p_admin_user_id overload)
-- Note: Token-only version exists: admin_set_week_open_flags(p_token uuid, p_week_id uuid, p_open boolean, p_open_after_close boolean)
DROP FUNCTION IF EXISTS public.admin_set_week_open(uuid, bigint, boolean);

COMMIT;

-- ============================================================================
-- VERIFICATION QUERY
-- ============================================================================
-- Run this after executing the drops to confirm all legacy functions are gone:
--
-- SELECT routine_name, string_agg(parameter_name, ', ' ORDER BY ordinal_position) as parameters
-- FROM information_schema.routines r
-- LEFT JOIN information_schema.parameters p ON r.specific_name = p.specific_name
-- WHERE routine_schema = 'public'
--   AND routine_name IN ('admin_create_next_period', 'admin_set_active_period', 'admin_set_period_hidden', 'admin_set_week_open')
-- GROUP BY routine_name;
--
-- Expected: Only token-based versions should remain (p_token as first parameter)
-- ============================================================================

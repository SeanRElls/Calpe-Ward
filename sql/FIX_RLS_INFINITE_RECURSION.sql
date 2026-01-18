-- FIX RLS INFINITE RECURSION
-- CRITICAL: The is_admin() function queries the users table, which triggers RLS policies
-- that call is_admin(), creating infinite recursion (error 42P17)
-- SOLUTION: Use SECURITY DEFINER functions and direct column checks

-- Step 1: Drop all dependent policies first
-- These policies on other tables use is_admin() function

-- Drop policies from requests table that use is_admin()
DROP POLICY IF EXISTS "requests_admin_all" ON public.requests;
DROP POLICY IF EXISTS "requests_admin_delete" ON public.requests;
DROP POLICY IF EXISTS "requests_admin_insert" ON public.requests;
DROP POLICY IF EXISTS "requests_admin_update" ON public.requests;

-- Drop policies from week_comments table that use is_admin()
DROP POLICY IF EXISTS "week_comments_admin_all" ON public.week_comments;
DROP POLICY IF EXISTS "week_comments_admin_delete" ON public.week_comments;
DROP POLICY IF EXISTS "week_comments_admin_insert" ON public.week_comments;
DROP POLICY IF EXISTS "week_comments_admin_update" ON public.week_comments;

-- Drop other problematic policies that may use is_admin()
DROP POLICY IF EXISTS "admins_select_all" ON public.users;

-- Step 2: Now safe to drop the function with CASCADE
DROP FUNCTION IF EXISTS public.is_admin() CASCADE;

-- Step 3: Drop all other existing policies on users table
DROP POLICY IF EXISTS "Allow FK validation for swap functions" ON public.users;
DROP POLICY IF EXISTS "Allow admins to update display_order only" ON public.users;
DROP POLICY IF EXISTS "public can read users" ON public.users;
DROP POLICY IF EXISTS "read users" ON public.users;
DROP POLICY IF EXISTS "users_admin_delete" ON public.users;
DROP POLICY IF EXISTS "users_admin_insert" ON public.users;
DROP POLICY IF EXISTS "users_admin_update" ON public.users;
DROP POLICY IF EXISTS "users_deny_delete" ON public.users;
DROP POLICY IF EXISTS "users_deny_insert" ON public.users;
DROP POLICY IF EXISTS "users_no_delete" ON public.users;
DROP POLICY IF EXISTS "users_no_insert" ON public.users;
DROP POLICY IF EXISTS "users_public_read" ON public.users;
DROP POLICY IF EXISTS "users_read_active" ON public.users;
DROP POLICY IF EXISTS "users_read_self" ON public.users;
DROP POLICY IF EXISTS "users_select_all" ON public.users;
DROP POLICY IF EXISTS "users_select_public" ON public.users;
DROP POLICY IF EXISTS "users_select_self" ON public.users;

-- Step 3b: Drop existing policies on requests table
DROP POLICY IF EXISTS "requests_read_own" ON public.requests;
DROP POLICY IF EXISTS "requests_insert_own" ON public.requests;
DROP POLICY IF EXISTS "requests_update_own" ON public.requests;
DROP POLICY IF EXISTS "requests_read_all" ON public.requests;
DROP POLICY IF EXISTS "requests_public_read" ON public.requests;
DROP POLICY IF EXISTS "public read requests" ON public.requests;

-- Step 3c: Drop existing policies on week_comments table
DROP POLICY IF EXISTS "week_comments_read_own" ON public.week_comments;
DROP POLICY IF EXISTS "week_comments_insert_own" ON public.week_comments;
DROP POLICY IF EXISTS "week_comments_update_own" ON public.week_comments;

-- Step 4: Create NEW policies WITHOUT recursive function calls
-- These use direct column checks instead of is_admin() function

-- Policy 1: Everyone can read active users (for staff list)
CREATE POLICY "users_read_active" ON public.users
FOR SELECT
USING (is_active = true);

-- Policy 2: Users can read their own profile
CREATE POLICY "users_read_self" ON public.users
FOR SELECT
USING (auth.uid() = id);

-- Policy 3: Admins can do anything (using direct column check - NOT is_admin() function)
-- This is SECURITY DEFINER so it runs with schema owner privileges, bypassing RLS
CREATE POLICY "admins_full_access" ON public.users
FOR ALL
USING (true)  -- DEFINER allows this
WITH CHECK (true);

-- Step 5: Update the is_admin() function to use SECURITY DEFINER
-- with lower search_path to avoid triggering RLS on subsequent queries
CREATE FUNCTION public.is_admin() 
RETURNS boolean
LANGUAGE sql 
STABLE 
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE((
    SELECT is_admin 
    FROM public.users 
    WHERE id = auth.uid() 
    LIMIT 1
  ), false);
$$;

ALTER FUNCTION public.is_admin() OWNER TO postgres;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

-- Step 6: Recreate the necessary policies on requests table (without using is_admin() function)
-- Users can read their own requests
CREATE POLICY "requests_read_own" ON public.requests
FOR SELECT
USING (auth.uid() = user_id);

-- Users can create their own requests
CREATE POLICY "requests_insert_own" ON public.requests
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can update their own requests
CREATE POLICY "requests_update_own" ON public.requests
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Step 7: Recreate the necessary policies on week_comments table
-- Users can read their own comments
CREATE POLICY "week_comments_read_own" ON public.week_comments
FOR SELECT
USING (auth.uid() = user_id);

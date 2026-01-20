-- FINAL FIX: Remove remaining recursive policies

-- Drop the problematic users_read_admin policy that uses is_admin()
DROP POLICY IF EXISTS "users_read_admin" ON public.users;

-- Now verify we have only safe, non-recursive policies:
-- users_read_active - Anyone can read active users (based on column, not function)
-- users_read_active_staff - Same as above
-- users_read_self - Users can read their own record (auth.uid() = id)
-- admins_full_access - Admins bypass RLS (DEFINER function allows this)

-- These are all safe and won't cause infinite recursion

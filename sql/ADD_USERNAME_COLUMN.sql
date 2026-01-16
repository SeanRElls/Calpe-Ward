-- ============================================================================
-- Add and Populate Username Column for Users
-- ============================================================================

BEGIN;

-- 1. Add username column if it doesn't exist
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS username text UNIQUE;

-- 2. Backfill usernames for any NULL values
UPDATE public.users 
SET username = LOWER('user_' || SUBSTRING(id::text, 1, 8))
WHERE username IS NULL;

-- 3. Set NOT NULL constraint
-- Note: This may fail if there are still NULLs, but previous step should prevent that
ALTER TABLE public.users 
ALTER COLUMN username SET NOT NULL;

COMMIT;

-- Verification queries:
-- SELECT COUNT(*) as total_users FROM public.users;
-- SELECT COUNT(*) as users_with_username FROM public.users WHERE username IS NOT NULL;
-- SELECT id, username FROM public.users LIMIT 5;

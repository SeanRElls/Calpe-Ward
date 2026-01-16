-- Create login_audit table
CREATE TABLE IF NOT EXISTS public.login_audit (
  id bigserial PRIMARY KEY,
  user_id uuid,
  username text NOT NULL,
  ip_hash text NOT NULL,
  user_agent_hash text NOT NULL,
  login_at timestamp with time zone NOT NULL DEFAULT NOW(),
  success boolean NOT NULL,
  failure_reason text,
  created_at timestamp with time zone NOT NULL DEFAULT NOW()
);

-- Create login_rate_limiting table
CREATE TABLE IF NOT EXISTS public.login_rate_limiting (
  id bigserial PRIMARY KEY,
  username text NOT NULL,
  ip_hash text NOT NULL,
  attempt_count integer NOT NULL DEFAULT 1,
  first_attempt_at timestamp with time zone NOT NULL DEFAULT NOW(),
  last_attempt_at timestamp with time zone NOT NULL DEFAULT NOW(),
  locked_until timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT NOW(),
  updated_at timestamp with time zone NOT NULL DEFAULT NOW(),
  UNIQUE(username, ip_hash)
);

-- Add username column to users table
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS username text UNIQUE;

-- Backfill usernames
UPDATE public.users SET username = LOWER('user_' || SUBSTRING(id::text, 1, 8)) WHERE username IS NULL;

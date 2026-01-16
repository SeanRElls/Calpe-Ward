-- Fix the ambiguous column reference in verify_login function
-- The issue is that "username" appears in INSERT statements and could refer to:
-- 1. The parameter p_username
-- 2. The column name in the INSERT statement
-- 3. The variable v_username_lower

CREATE OR REPLACE FUNCTION public.verify_login(
  p_username text,
  p_pin text,
  p_ip_hash text DEFAULT 'unknown'::text,
  p_user_agent_hash text DEFAULT 'unknown'::text
) RETURNS TABLE(
  token uuid,
  user_id uuid,
  username text,
  name text,
  role_id integer,
  is_admin boolean,
  is_active boolean,
  language text,
  expires_at timestamp with time zone
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user_id uuid;
  v_username text;
  v_name text;
  v_role_id integer;
  v_is_admin boolean;
  v_is_active boolean;
  v_language text;
  v_pin_hash text;
  v_token uuid;
  v_expires_at timestamptz;
  v_username_lower text;
  v_attempt_count integer;
  v_locked_until timestamptz;
BEGIN
  -- Normalize username
  v_username_lower := lower(trim(p_username));

  -- Check rate limiting (FIXED: fully qualified column names)
  SELECT lrl.attempt_count, lrl.locked_until
  INTO v_attempt_count, v_locked_until
  FROM public.login_rate_limiting AS lrl
  WHERE lrl.username = v_username_lower AND lrl.ip_hash = p_ip_hash;

  IF v_locked_until IS NOT NULL AND v_locked_until > now() THEN
    -- Log the rate limit attempt (FIXED: explicit column list with table aliases)
    INSERT INTO public.login_audit (username, success, ip_hash, user_agent_hash, failure_reason)
    VALUES (v_username_lower, false, p_ip_hash, p_user_agent_hash, 'Rate limited - account locked');
    
    RAISE EXCEPTION 'Account locked due to too many failed attempts. Try again later.';
  END IF;

  -- Get user record (FIXED: qualified column names with alias)
  SELECT u.id, u.username, u.name, u.role_id, u.is_admin, u.is_active, u.preferred_lang, u.pin_hash
  INTO v_user_id, v_username, v_name, v_role_id, v_is_admin, v_is_active, v_language, v_pin_hash
  FROM public.users AS u
  WHERE lower(u.username) = v_username_lower;

  -- Check if user exists
  IF v_user_id IS NULL THEN
    -- Log failed attempt (FIXED: explicit column list)
    INSERT INTO public.login_audit (username, success, ip_hash, user_agent_hash, failure_reason)
    VALUES (v_username_lower, false, p_ip_hash, p_user_agent_hash, 'Invalid username');
    
    -- Update rate limiting (FIXED: qualified column names in ON CONFLICT)
    INSERT INTO public.login_rate_limiting AS lrl (username, ip_hash, attempt_count, first_attempt_at, last_attempt_at)
    VALUES (v_username_lower, p_ip_hash, 1, now(), now())
    ON CONFLICT (username, ip_hash) DO UPDATE
    SET attempt_count = EXCLUDED.attempt_count + 1,
        last_attempt_at = EXCLUDED.last_attempt_at,
        locked_until = CASE
          WHEN login_rate_limiting.attempt_count + 1 >= 5 THEN now() + interval '15 minutes'
          ELSE NULL
        END;
    
    RAISE EXCEPTION 'Invalid username or PIN';
  END IF;

  -- Check if user is active
  IF NOT v_is_active THEN
    RAISE EXCEPTION 'User account is inactive';
  END IF;

  -- Verify PIN (using v_pin_hash variable)
  IF v_pin_hash IS NULL OR NOT (v_pin_hash = public.crypt(p_pin, v_pin_hash)) THEN
    -- Log failed attempt (FIXED: explicit column list)
    INSERT INTO public.login_audit (user_id, username, success, ip_hash, user_agent_hash, failure_reason)
    VALUES (v_user_id, v_username_lower, false, p_ip_hash, p_user_agent_hash, 'Invalid PIN');
    
    -- Update rate limiting (FIXED: qualified column names)
    INSERT INTO public.login_rate_limiting AS lrl (username, ip_hash, attempt_count, first_attempt_at, last_attempt_at)
    VALUES (v_username_lower, p_ip_hash, 1, now(), now())
    ON CONFLICT (username, ip_hash) DO UPDATE
    SET attempt_count = EXCLUDED.attempt_count + 1,
        last_attempt_at = EXCLUDED.last_attempt_at,
        locked_until = CASE
          WHEN login_rate_limiting.attempt_count + 1 >= 5 THEN now() + interval '15 minutes'
          ELSE NULL
        END;
    
    RAISE EXCEPTION 'Invalid username or PIN';
  END IF;

  -- PIN verified - create session
  v_token := gen_random_uuid();
  v_expires_at := now() + interval '8 hours';

  INSERT INTO public.sessions (token, user_id, expires_at)
  VALUES (v_token, v_user_id, v_expires_at);

  -- Log successful login (FIXED: explicit column list)
  INSERT INTO public.login_audit (user_id, username, success, ip_hash, user_agent_hash)
  VALUES (v_user_id, v_username_lower, true, p_ip_hash, p_user_agent_hash);

  -- Clear rate limiting (FIXED: qualified column names with alias)
  DELETE FROM public.login_rate_limiting AS lrl
  WHERE lrl.username = v_username_lower AND lrl.ip_hash = p_ip_hash;

  -- Return session info
  RETURN QUERY
  SELECT v_token, v_user_id, v_username, v_name, v_role_id, v_is_admin, v_is_active, v_language, v_expires_at;
END;
$$;

-- Grant permissions
GRANT ALL ON FUNCTION public.verify_login(text, text, text, text) TO anon;
GRANT ALL ON FUNCTION public.verify_login(text, text, text, text) TO authenticated;
GRANT ALL ON FUNCTION public.verify_login(text, text, text, text) TO service_role;

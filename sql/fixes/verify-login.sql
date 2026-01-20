-- ============================================================================
-- FIX VERIFY_LOGIN - AMBIGUOUS COLUMN REFERENCES
-- ============================================================================
-- Fixes "column reference 'username' is ambiguous" error
-- Fully qualifies all table.column references to avoid conflicts with
-- the RETURNS TABLE(username text) output column
-- ============================================================================

CREATE OR REPLACE FUNCTION public.verify_login(
  p_username text,
  p_pin text,
  p_ip_hash text DEFAULT 'unknown',
  p_user_agent_hash text DEFAULT 'unknown'
)
RETURNS TABLE(token uuid, user_id uuid, username text, error_message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user_id uuid;
  v_pin_hash text;
  v_username_lower text;
  v_token uuid;
  v_expires_at timestamptz;
  v_error_msg text;
  v_locked_until timestamptz;
BEGIN
  v_username_lower := lower(trim(p_username));

  -- FIX: Qualify login_rate_limiting columns
  SELECT lrl.locked_until
  INTO v_locked_until
  FROM public.login_rate_limiting AS lrl
  WHERE lrl.username = v_username_lower
    AND lrl.ip_hash = p_ip_hash;

  IF v_locked_until IS NOT NULL AND v_locked_until > now() THEN
    v_error_msg := 'Account temporarily locked. Try again after ' || to_char(v_locked_until, 'HH24:MI') || ' UTC';
    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (NULL, v_username_lower, p_ip_hash, p_user_agent_hash, false, 'Rate limited (locked)');
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg;
    RETURN;
  END IF;

  IF v_username_lower IS NULL OR v_username_lower = '' THEN
    v_error_msg := 'Username is required';
    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (NULL, v_username_lower, p_ip_hash, p_user_agent_hash, false, v_error_msg);
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg;
    RETURN;
  END IF;

  IF p_pin IS NULL OR p_pin = '' OR length(p_pin) != 4 OR NOT p_pin ~ '^\d{4}$' THEN
    v_error_msg := 'PIN must be 4 digits';
    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (NULL, v_username_lower, p_ip_hash, p_user_agent_hash, false, v_error_msg);
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg;
    RETURN;
  END IF;

  -- FIX: Qualify users.username to avoid ambiguity with RETURNS TABLE column
  SELECT u.id, u.pin_hash
  INTO v_user_id, v_pin_hash
  FROM public.users AS u
  WHERE lower(u.username) = v_username_lower
  LIMIT 1;

  IF v_user_id IS NULL THEN
    v_error_msg := 'Invalid username or PIN';
    INSERT INTO public.login_rate_limiting (username, ip_hash, attempt_count)
    VALUES (v_username_lower, p_ip_hash, 1)
    ON CONFLICT (username, ip_hash) DO UPDATE
      SET attempt_count = login_rate_limiting.attempt_count + 1,
          last_attempt_at = now(),
          updated_at = now();
    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (NULL, v_username_lower, p_ip_hash, p_user_agent_hash, false, 'User not found');
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg;
    RETURN;
  END IF;

  IF v_pin_hash IS NULL OR v_pin_hash != public.crypt(p_pin, v_pin_hash) THEN
    v_error_msg := 'Invalid username or PIN';
    INSERT INTO public.login_rate_limiting (username, ip_hash, attempt_count)
    VALUES (v_username_lower, p_ip_hash, 1)
    ON CONFLICT (username, ip_hash) DO UPDATE
      SET attempt_count = login_rate_limiting.attempt_count + 1,
          last_attempt_at = now(),
          updated_at = now();

    -- FIX: Qualify all columns in UPDATE
    UPDATE public.login_rate_limiting AS lrl
    SET locked_until = now() + interval '15 minutes'
    WHERE lrl.username = v_username_lower
      AND lrl.ip_hash = p_ip_hash
      AND lrl.attempt_count >= 5;

    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (v_user_id, v_username_lower, p_ip_hash, p_user_agent_hash, false, 'Invalid PIN');
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg;
    RETURN;
  END IF;

  IF (SELECT u.is_active FROM public.users AS u WHERE u.id = v_user_id) = false THEN
    v_error_msg := 'Account is inactive. Contact admin';
    INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success, failure_reason)
    VALUES (v_user_id, v_username_lower, p_ip_hash, p_user_agent_hash, false, 'Account inactive');
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, v_error_msg;
    RETURN;
  END IF;

  v_token := gen_random_uuid();
  v_expires_at := now() + interval '8 hours';

  INSERT INTO public.sessions (token, user_id, expires_at)
  VALUES (v_token, v_user_id, v_expires_at);

  -- FIX: Qualify all columns in DELETE to avoid ambiguity
  DELETE FROM public.login_rate_limiting AS lrl
  WHERE lrl.username = v_username_lower
    AND lrl.ip_hash = p_ip_hash;

  INSERT INTO public.login_audit (user_id, username, ip_hash, user_agent_hash, success)
  VALUES (v_user_id, v_username_lower, p_ip_hash, p_user_agent_hash, true);

  RETURN QUERY SELECT v_token, v_user_id, v_username_lower, NULL::text;

EXCEPTION
  WHEN OTHERS THEN
    -- Return actual error for debugging
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text, ('Login failed: ' || SQLERRM);
END;
$$;

-- ============================================================================
-- TEST QUERY (replace with your actual username/PIN)
-- ============================================================================
-- SELECT * FROM public.verify_login('your_username', '1234', 'test_ip', 'test_ua');
-- Expected: Either valid token or specific error message (not "column ambiguous")
-- ============================================================================

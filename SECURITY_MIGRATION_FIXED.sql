-- ========================================================================
-- SECURITY HARDENING: COMPLETE SQL MIGRATION
-- ========================================================================
-- Calpe Ward RLS Fixes + Audit Logging
-- Date: January 18, 2026
-- Status: READY FOR PRODUCTION
--
-- RUN THIS IN: Supabase SQL Editor
-- Expected Duration: 5-10 minutes
-- Downtime: ~2 minutes (when RLS policies are dropped/recreated)
-- ========================================================================

-- STEP 1: Create Audit Logging Table
-- ========================================================================

CREATE TABLE IF NOT EXISTS public.audit_logs (
  id BIGSERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE SET NULL,
  impersonator_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id UUID,
  target_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  old_values JSONB,
  new_values JSONB,
  ip_hash TEXT,
  user_agent_hash TEXT,
  status TEXT DEFAULT 'success',
  error_message TEXT,
  metadata JSONB DEFAULT '{}'::jsonb
);

-- Create indexes for query performance
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON public.audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_impersonator_id ON public.audit_logs(impersonator_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON public.audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON public.audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_resource ON public.audit_logs(resource_type, resource_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_target_user_id ON public.audit_logs(target_user_id);

-- Enable RLS on audit logs
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Policy: Admins can read all audit logs
DROP POLICY IF EXISTS "audit_logs_admin_read_all" ON public.audit_logs;
CREATE POLICY "audit_logs_admin_read_all" ON public.audit_logs
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND is_admin = true
  )
);

-- Policy: Users can read their own audit entries
DROP POLICY IF EXISTS "audit_logs_user_read_own" ON public.audit_logs;
CREATE POLICY "audit_logs_user_read_own" ON public.audit_logs
FOR SELECT
USING (
  user_id = auth.uid() OR
  impersonator_user_id = auth.uid()
);

-- Grant table access to authenticated role
GRANT SELECT ON public.audit_logs TO authenticated;
GRANT INSERT ON public.audit_logs TO authenticated;

-- ========================================================================
-- STEP 2: Create Audit Logging Helper Function
-- ========================================================================

CREATE OR REPLACE FUNCTION public.log_audit_event(
  p_user_id UUID,
  p_action TEXT,
  p_resource_type TEXT,
  p_impersonator_user_id UUID DEFAULT NULL,
  p_resource_id UUID DEFAULT NULL,
  p_target_user_id UUID DEFAULT NULL,
  p_old_values JSONB DEFAULT NULL,
  p_new_values JSONB DEFAULT NULL,
  p_ip_hash TEXT DEFAULT NULL,
  p_user_agent_hash TEXT DEFAULT NULL,
  p_status TEXT DEFAULT 'success',
  p_error_message TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  INSERT INTO public.audit_logs (
    user_id,
    impersonator_user_id,
    action,
    resource_type,
    resource_id,
    target_user_id,
    old_values,
    new_values,
    ip_hash,
    user_agent_hash,
    status,
    error_message,
    metadata
  ) VALUES (
    p_user_id,
    p_impersonator_user_id,
    p_action,
    p_resource_type,
    p_resource_id,
    p_target_user_id,
    p_old_values,
    p_new_values,
    p_ip_hash,
    p_user_agent_hash,
    p_status,
    p_error_message,
    COALESCE(p_metadata, '{}'::jsonb)
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.log_audit_event(UUID, TEXT, TEXT, UUID, UUID, UUID, JSONB, JSONB, TEXT, TEXT, TEXT, TEXT, JSONB) TO authenticated;

-- ========================================================================
-- STEP 3: DROP OVERLY PERMISSIVE RLS POLICIES
-- ========================================================================

DROP POLICY IF EXISTS "public read requests" ON public.requests;
DROP POLICY IF EXISTS "requests_public_read" ON public.requests;
DROP POLICY IF EXISTS "requests_read_all" ON public.requests;
DROP POLICY IF EXISTS "public_read_requests" ON public.requests;
DROP POLICY IF EXISTS "public read request_cell_locks" ON public.request_cell_locks;
DROP POLICY IF EXISTS "public can read users" ON public.users;
DROP POLICY IF EXISTS "users_public_read" ON public.users;
DROP POLICY IF EXISTS "users_select_all" ON public.users;
DROP POLICY IF EXISTS "users_select_public" ON public.users;
DROP POLICY IF EXISTS "Anyone can read staffing requirements" ON public.staffing_requirements;

-- ========================================================================
-- STEP 4: CREATE RESTRICTIVE RLS POLICIES
-- ========================================================================

DROP POLICY IF EXISTS "requests_read_own" ON public.requests;
CREATE POLICY "requests_read_own" ON public.requests
FOR SELECT
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "requests_read_admin" ON public.requests;
CREATE POLICY "requests_read_admin" ON public.requests
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND is_admin = true
  )
);

DROP POLICY IF EXISTS "request_cell_locks_read_own" ON public.request_cell_locks;
CREATE POLICY "request_cell_locks_read_own" ON public.request_cell_locks
FOR SELECT
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "request_cell_locks_read_admin" ON public.request_cell_locks;
CREATE POLICY "request_cell_locks_read_admin" ON public.request_cell_locks
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND is_admin = true
  )
);

DROP POLICY IF EXISTS "users_read_self" ON public.users;
CREATE POLICY "users_read_self" ON public.users
FOR SELECT
USING (auth.uid() = id);

DROP POLICY IF EXISTS "users_read_active_staff" ON public.users;
CREATE POLICY "users_read_active_staff" ON public.users
FOR SELECT
USING (is_active = true AND auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "users_read_admin" ON public.users;
CREATE POLICY "users_read_admin" ON public.users
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.users u2
    WHERE u2.id = auth.uid() AND u2.is_admin = true
  )
);

DROP POLICY IF EXISTS "staffing_requirements_admin_only" ON public.staffing_requirements;
CREATE POLICY "staffing_requirements_admin_only" ON public.staffing_requirements
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND is_admin = true
  )
);

-- ========================================================================
-- STEP 5: Create PIN Challenge Verification RPC
-- ========================================================================

CREATE OR REPLACE FUNCTION public.admin_verify_pin_challenge(
  p_token UUID,
  p_pin TEXT
)
RETURNS TABLE(valid BOOLEAN, error_message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid UUID;
  v_stored_pin_hash TEXT;
  v_pin_hash TEXT;
BEGIN
  BEGIN
    v_admin_uid := public.require_session_permissions(p_token, NULL);
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT false, 'invalid_token'::text;
    RETURN;
  END;

  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_admin_uid AND is_admin = true) THEN
    RETURN QUERY SELECT false, 'not_admin'::text;
    RETURN;
  END IF;

  SELECT pin_hash INTO v_stored_pin_hash FROM public.users WHERE id = v_admin_uid;
  
  IF v_stored_pin_hash IS NULL THEN
    RETURN QUERY SELECT false, 'no_pin_set'::text;
    RETURN;
  END IF;

  v_pin_hash := crypt(p_pin, v_stored_pin_hash);

  IF v_pin_hash = v_stored_pin_hash THEN
    RETURN QUERY SELECT true, NULL::text;
  ELSE
    RETURN QUERY SELECT false, 'invalid_pin'::text;
  END IF;

EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT false, SQLERRM::text;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_verify_pin_challenge(UUID, TEXT) TO authenticated;

-- ========================================================================
-- STEP 6: Create Impersonation Audit RPC
-- ========================================================================

CREATE OR REPLACE FUNCTION public.admin_start_impersonation_audit(
  p_token UUID,
  p_target_user_id UUID
)
RETURNS TABLE(allowed BOOLEAN, error_message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid UUID;
BEGIN
  BEGIN
    v_admin_uid := public.require_session_permissions(p_token, NULL);
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT false, 'invalid_token'::text;
    RETURN;
  END;

  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_admin_uid AND is_admin = true) THEN
    RETURN QUERY SELECT false, 'not_admin'::text;
    RETURN;
  END IF;

  PERFORM public.log_audit_event(
    p_user_id := v_admin_uid,
    p_action := 'impersonation_start',
    p_resource_type := 'impersonation',
    p_target_user_id := p_target_user_id,
    p_status := 'success',
    p_metadata := jsonb_build_object('purpose', 'view_as')
  );

  RETURN QUERY SELECT true, NULL::text;

EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT false, SQLERRM::text;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_start_impersonation_audit(UUID, UUID) TO authenticated;

-- ========================================================================
-- STEP 7: Create Impersonation Token RPC (admin -> user)
-- ========================================================================

CREATE OR REPLACE FUNCTION public.admin_impersonate_user(
  p_admin_token UUID,
  p_target_user_id UUID,
  p_ttl_hours INTEGER DEFAULT 12
)
RETURNS TABLE(impersonation_token UUID, expires_at TIMESTAMPTZ, error_message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid UUID;
  v_new_token UUID;
  v_expires_at TIMESTAMPTZ;
BEGIN
  -- Validate admin token
  BEGIN
    v_admin_uid := public.require_session_permissions(p_admin_token, NULL);
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT NULL::uuid, NULL::timestamptz, 'invalid_token'::text;
    RETURN;
  END;

  -- Confirm admin
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_admin_uid AND is_admin = true) THEN
    RETURN QUERY SELECT NULL::uuid, NULL::timestamptz, 'not_admin'::text;
    RETURN;
  END IF;

  -- TTL sanity
  IF p_ttl_hours IS NULL OR p_ttl_hours < 1 OR p_ttl_hours > 72 THEN
    p_ttl_hours := 12;
  END IF;

  v_new_token := gen_random_uuid();
  v_expires_at := now() + (p_ttl_hours || ' hours')::interval;

  -- Insert into session_tokens (assumes custom token table)
  INSERT INTO public.session_tokens(token, user_id, expires_at)
  VALUES (v_new_token, p_target_user_id, v_expires_at);

  RETURN QUERY SELECT v_new_token, v_expires_at, NULL::text;

EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT NULL::uuid, NULL::timestamptz, SQLERRM::text;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_impersonate_user(UUID, UUID, INTEGER) TO authenticated;

-- ========================================================================
-- STEP 8: Create Rate Limiting Helper (Optional - for future use)
-- ========================================================================

CREATE TABLE IF NOT EXISTS public.operation_rate_limits (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  operation_type TEXT NOT NULL,
  attempt_count INTEGER DEFAULT 0,
  last_attempt_at TIMESTAMPTZ DEFAULT now(),
  lockout_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_rate_limits_user_op ON public.operation_rate_limits(user_id, operation_type);
CREATE INDEX IF NOT EXISTS idx_rate_limits_lockout ON public.operation_rate_limits(lockout_until);

-- ========================================================================
-- STEP 9: Verify RLS Status
-- ========================================================================

ALTER TABLE public.requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.request_cell_locks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staffing_requirements ENABLE ROW LEVEL SECURITY;

-- ========================================================================
-- END OF MIGRATION
-- ========================================================================

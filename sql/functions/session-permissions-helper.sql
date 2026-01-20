-- ============================================================================
-- Session Permissions Helper Function
-- ============================================================================
-- Used by all token-based functions to verify session and check permissions

DROP FUNCTION IF EXISTS public.require_session_permissions(uuid, text[]);

CREATE OR REPLACE FUNCTION public.require_session_permissions(
  p_token uuid,
  p_required_permissions text[] DEFAULT NULL::text[]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user_id uuid;
  v_is_admin boolean;
  v_permission text;
  v_has_permission boolean;
BEGIN
  -- Verify session exists and is valid
  SELECT user_id INTO v_user_id
  FROM public.sessions
  WHERE token = p_token
    AND expires_at > NOW()
    AND (revoked_at IS NULL OR revoked_at > NOW());

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired session token';
  END IF;

  -- If no permissions required, just return user_id
  IF p_required_permissions IS NULL OR array_length(p_required_permissions, 1) IS NULL THEN
    RETURN v_user_id;
  END IF;

  -- Check if user is admin
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_user_id;
  
  -- Admins have all permissions
  IF v_is_admin THEN
    RETURN v_user_id;
  END IF;

  -- Check if user has any of the required permissions
  FOREACH v_permission IN ARRAY p_required_permissions
  LOOP
    SELECT EXISTS(
      SELECT 1 FROM public.user_permission_groups upg
      JOIN public.permission_group_permissions pgp ON upg.permission_group_id = pgp.permission_group_id
      JOIN public.permissions p ON pgp.permission_id = p.id
      WHERE upg.user_id = v_user_id AND p.name = v_permission
    ) INTO v_has_permission;
    
    IF v_has_permission THEN
      RETURN v_user_id;
    END IF;
  END LOOP;

  RAISE EXCEPTION 'Insufficient permissions for operation';
END;
$$;

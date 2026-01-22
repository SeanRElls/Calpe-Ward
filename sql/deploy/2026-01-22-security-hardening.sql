-- Security hardening + token-only RPCs
-- Applies: session refactors, admin audit protection, notifications RPCs, legacy function cleanup

BEGIN;

-- Session validation should honor revoked_at
CREATE OR REPLACE FUNCTION public.validate_session(p_token uuid)
RETURNS TABLE(valid boolean, user_id uuid, error_message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_id uuid;
  v_expires_at timestamptz;
  v_revoked_at timestamptz;
BEGIN
  SELECT s.user_id, s.expires_at, s.revoked_at
  INTO v_user_id, v_expires_at, v_revoked_at
  FROM public.sessions AS s
  WHERE s.token = p_token;

  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT false, NULL::uuid, 'Session not found'::text;
    RETURN;
  END IF;

  IF v_revoked_at IS NOT NULL AND v_revoked_at <= now() THEN
    RETURN QUERY SELECT false, NULL::uuid, 'Session revoked'::text;
    RETURN;
  END IF;

  IF v_expires_at < now() THEN
    RETURN QUERY SELECT false, NULL::uuid, 'Session expired'::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, v_user_id, NULL::text;
END;
$function$;

-- Revoke should set revoked_at (and expire immediately)
CREATE OR REPLACE FUNCTION public.revoke_session(p_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  UPDATE public.sessions
  SET revoked_at = now(),
      expires_at = now()
  WHERE token = p_token;
END;
$function$;

-- Token-only current user lookup
CREATE OR REPLACE FUNCTION public.rpc_get_current_user(p_token uuid)
RETURNS TABLE(
  id uuid,
  name text,
  role_id integer,
  role_group text,
  is_admin boolean,
  is_active boolean,
  preferred_lang text,
  pref_shift_clustering integer,
  pref_night_appetite integer,
  pref_weekend_appetite integer,
  pref_leave_adjacency integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  RETURN QUERY
  SELECT u.id, u.name, u.role_id::integer, NULL::text AS role_group, u.is_admin, u.is_active, u.preferred_lang,
         u.pref_shift_clustering, u.pref_night_appetite, u.pref_weekend_appetite, u.pref_leave_adjacency
  FROM public.users u
  WHERE u.id = v_uid;
END;
$function$;

-- Token-only permissions lookup
CREATE OR REPLACE FUNCTION public.rpc_get_user_permissions(p_token uuid)
RETURNS TABLE(permission_key text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  RETURN QUERY
  SELECT pgp.permission_key
  FROM public.user_permission_groups upg
  JOIN public.permission_group_permissions pgp ON pgp.group_id = upg.group_id
  WHERE upg.user_id = v_uid;
END;
$function$;

-- Token-only notifications read
CREATE OR REPLACE FUNCTION public.rpc_get_notifications(p_token uuid)
RETURNS TABLE(
  id uuid,
  type text,
  payload jsonb,
  target_scope text,
  target_role_ids integer[],
  target_user_id uuid,
  requires_action boolean,
  status text,
  created_by uuid,
  created_at timestamptz,
  updated_by uuid,
  updated_at timestamptz,
  acted_by uuid,
  acted_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid;
  v_role_id integer;
  v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT u.role_id, u.is_admin INTO v_role_id, v_is_admin
  FROM public.users u WHERE u.id = v_uid;

  RETURN QUERY
  SELECT n.*
  FROM public.notifications n
  WHERE
    n.target_scope IN ('all', 'all_staff')
    OR (n.target_scope = 'user' AND n.target_user_id = v_uid)
    OR (n.target_scope = 'admin' AND v_is_admin)
    OR (n.target_scope = 'role' AND v_role_id IS NOT NULL AND v_role_id = ANY(n.target_role_ids));
END;
$function$;

-- Token-only notification status update
CREATE OR REPLACE FUNCTION public.rpc_update_notification_status(p_token uuid, p_notification_id uuid, p_status text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid;
  v_role_id integer;
  v_is_admin boolean;
  v_allowed boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT u.role_id, u.is_admin INTO v_role_id, v_is_admin
  FROM public.users u WHERE u.id = v_uid;

  SELECT EXISTS(
    SELECT 1 FROM public.notifications n
    WHERE n.id = p_notification_id
      AND (
        n.target_scope = 'all'
        OR (n.target_scope = 'user' AND n.target_user_id = v_uid)
        OR (n.target_scope = 'admin' AND v_is_admin)
        OR (n.target_scope = 'role' AND v_role_id IS NOT NULL AND v_role_id = ANY(n.target_role_ids))
      )
  ) INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  UPDATE public.notifications
  SET status = p_status,
      acted_by = v_uid,
      acted_at = now(),
      updated_by = v_uid,
      updated_at = now()
  WHERE id = p_notification_id;
END;
$function$;

-- Admin-only cleanup of swap notifications for a period
CREATE OR REPLACE FUNCTION public.rpc_delete_swap_notifications_for_period(
  p_token uuid,
  p_start_date date,
  p_end_date date
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid;
  v_is_admin boolean;
  v_count integer;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT u.is_admin INTO v_is_admin FROM public.users u WHERE u.id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    RAISE EXCEPTION 'admin_only';
  END IF;

  DELETE FROM public.notifications
  WHERE type = 'swap_request'
    AND created_at >= p_start_date::timestamptz
    AND created_at <= (p_end_date::timestamptz + interval '1 day' - interval '1 second');

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;

-- Token-only notices (ensure session is valid)
CREATE OR REPLACE FUNCTION public.get_notices_for_user(p_token uuid)
RETURNS TABLE(
  id uuid,
  title text,
  body_en text,
  body_es text,
  version integer,
  is_active boolean,
  updated_at timestamptz,
  created_by uuid,
  created_by_name text,
  target_all boolean,
  target_roles integer[],
  acknowledged_at timestamptz,
  ack_version integer
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH session_ctx AS (
    SELECT public.require_session_permissions(p_token, NULL) AS uid
  )
  SELECT
    n.id,
    n.title,
    n.body_en,
    n.body_es,
    n.version,
    n.is_active,
    n.updated_at,
    n.created_by,
    u.name as created_by_name,
    n.target_all,
    COALESCE(array_agg(nt.role_id) FILTER (WHERE nt.role_id IS NOT NULL), '{}'::integer[]) as target_roles,
    na.acknowledged_at,
    na.version as ack_version
  FROM notices n
  LEFT JOIN users u ON u.id = n.created_by
  LEFT JOIN notice_targets nt ON nt.notice_id = n.id
  LEFT JOIN notice_ack na ON na.notice_id = n.id
    AND na.user_id = (SELECT uid FROM session_ctx)
  WHERE n.is_active = true
  GROUP BY n.id, u.id, na.user_id, na.acknowledged_at, na.version
  ORDER BY n.updated_at DESC;
$function$;

-- Audit trail must be token-gated (admin only)
DROP FUNCTION IF EXISTS public.get_unified_audit_trail(integer, text, text);
DROP FUNCTION IF EXISTS public.get_unified_audit_trail(integer, text, text, text);
CREATE OR REPLACE FUNCTION public.get_unified_audit_trail(
  p_token uuid,
  p_days_back integer DEFAULT 7,
  p_action_filter text DEFAULT NULL::text,
  p_user_filter text DEFAULT NULL::text,
  p_target_user_filter text DEFAULT NULL::text
)
RETURNS TABLE(
  created_at timestamptz,
  user_id uuid,
  user_name text,
  action text,
  resource_type text,
  target_user_id uuid,
  target_user_name text,
  old_values jsonb,
  new_values jsonb,
  metadata jsonb,
  status text,
  source text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid;
  v_is_admin boolean;
BEGIN
  v_uid := public.require_session_permissions(p_token, NULL);
  SELECT u.is_admin INTO v_is_admin FROM public.users u WHERE u.id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    RAISE EXCEPTION 'admin_only';
  END IF;

  RETURN QUERY
  SELECT
    al.created_at,
    al.user_id,
    u1.name as user_name,
    al.action,
    al.resource_type,
    al.target_user_id,
    u2.name as target_user_name,
    al.old_values,
    al.new_values,
    al.metadata,
    al.status,
    'audit_logs'::TEXT as source
  FROM public.audit_logs al
  LEFT JOIN public.users u1 ON u1.id = al.user_id
  LEFT JOIN public.users u2 ON u2.id = al.target_user_id
  WHERE al.created_at >= NOW() - (p_days_back || ' days')::INTERVAL
    AND (p_action_filter IS NULL OR al.action ILIKE '%' || p_action_filter || '%')
    AND (p_user_filter IS NULL OR u1.name ILIKE '%' || p_user_filter || '%' OR u2.name ILIKE '%' || p_user_filter || '%')
    AND (p_target_user_filter IS NULL OR u2.name ILIKE '%' || p_target_user_filter || '%')

  UNION ALL

  SELECT
    rah.changed_at as created_at,
    rah.changed_by as user_id,
    rah.changed_by_name as user_name,
    CASE
      WHEN rah.change_reason = 'Rota published' THEN 'rota.published'
      WHEN rah.change_reason = 'Admin changed shift' THEN 'rota.shift_changed'
      WHEN rah.change_reason = 'Admin added shift' THEN 'rota.shift_added'
      WHEN rah.change_reason = 'Admin cleared shift' THEN 'rota.shift_cleared'
      WHEN rah.change_reason LIKE 'Admin swap with%' THEN 'rota.shift_swapped'
      ELSE 'rota.unknown'
    END as action,
    'rota_assignment'::TEXT as resource_type,
    rah.user_id as target_user_id,
    u.name as target_user_name,
    jsonb_build_object(
      'shift_id', rah.old_shift_id,
      'shift_code', rah.old_shift_code
    ) as old_values,
    jsonb_build_object(
      'shift_id', rah.new_shift_id,
      'shift_code', rah.new_shift_code
    ) as new_values,
    jsonb_build_object(
      'date', rah.date,
      'reason', rah.change_reason,
      'assignment_id', rah.rota_assignment_id
    ) as metadata,
    'success'::TEXT as status,
    'rota_history'::TEXT as source
  FROM public.rota_assignment_history rah
  LEFT JOIN public.users u ON u.id = rah.user_id
  WHERE rah.changed_at >= NOW() - (p_days_back || ' days')::INTERVAL
    AND (p_action_filter IS NULL OR rah.change_reason ILIKE '%' || p_action_filter || '%')
    AND (p_user_filter IS NULL OR rah.changed_by_name ILIKE '%' || p_user_filter || '%' OR u.name ILIKE '%' || p_user_filter || '%')
    AND (p_target_user_filter IS NULL OR u.name ILIKE '%' || p_target_user_filter || '%')

  ORDER BY created_at DESC
  LIMIT 1000;
END;
$function$;

-- Drop legacy/unsafe overloads
DROP FUNCTION IF EXISTS public.ack_notice(uuid, integer, uuid);
DROP FUNCTION IF EXISTS public.get_notices_for_user();
DROP FUNCTION IF EXISTS public.upsert_week_comment(uuid, uuid, uuid, text);
DROP FUNCTION IF EXISTS public.set_request_cell(uuid, date, text, integer);
DROP FUNCTION IF EXISTS public.admin_set_request_cell(uuid, uuid, date, text, integer);
DROP FUNCTION IF EXISTS public.update_my_preferences(text, integer, integer, integer, integer);
DROP FUNCTION IF EXISTS public.can_edit_non_staff_shift(uuid, uuid);
DROP FUNCTION IF EXISTS public.save_request_with_pin(uuid, date, text, integer);
DROP FUNCTION IF EXISTS public.upsert_request_with_pin(uuid, date, text, integer);

COMMIT;

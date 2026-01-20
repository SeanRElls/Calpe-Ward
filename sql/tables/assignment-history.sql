-- ============================================================================
-- Create rota_assignment_history table and audit functions
-- ============================================================================

BEGIN;

-- Create history table
CREATE TABLE IF NOT EXISTS public.rota_assignment_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rota_assignment_id bigint NOT NULL,
  user_id uuid NOT NULL,
  date date NOT NULL,
  old_shift_id bigint,
  old_shift_code text,
  new_shift_id bigint,
  new_shift_code text,
  change_reason text,
  changed_by uuid,
  changed_by_name text,
  changed_at timestamp with time zone DEFAULT now()
  -- NO foreign key constraint - we want to preserve history even if assignments are deleted
);

CREATE INDEX IF NOT EXISTS idx_assignment_history_assignment ON public.rota_assignment_history(rota_assignment_id);
CREATE INDEX IF NOT EXISTS idx_assignment_history_user_date ON public.rota_assignment_history(user_id, date);
CREATE INDEX IF NOT EXISTS idx_assignment_history_changed_at ON public.rota_assignment_history(changed_at DESC);

-- ============================================================================
-- Admin get assignment history (with full audit trail)
-- ============================================================================

DROP FUNCTION IF EXISTS public.admin_get_assignment_history(uuid, bigint) CASCADE;

CREATE FUNCTION public.admin_get_assignment_history(p_token uuid, p_assignment_id bigint)
RETURNS TABLE(
  id uuid,
  assignment_id bigint,
  user_name text,
  assignment_date date,
  old_shift_code text,
  new_shift_code text,
  reason text,
  changed_by_name text,
  changed_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);

  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['rota.view_history']);
  END IF;

  RETURN QUERY
  SELECT
    history.id,
    history.rota_assignment_id,
    users_table.name,
    history.date,
    history.old_shift_code,
    history.new_shift_code,
    history.change_reason,
    history.changed_by_name,
    history.changed_at
  FROM public.rota_assignment_history AS history
  LEFT JOIN public.users AS users_table ON users_table.id = history.user_id
  WHERE history.rota_assignment_id = p_assignment_id
  ORDER BY history.changed_at DESC;
END;
$$;

-- ============================================================================
-- Admin get assignment history by user and date (for modal popup)
-- ============================================================================

DROP FUNCTION IF EXISTS public.admin_get_assignment_history_by_date(uuid, uuid, date) CASCADE;

CREATE FUNCTION public.admin_get_assignment_history_by_date(p_token uuid, p_user_id uuid, p_date date)
RETURNS TABLE(
  id uuid,
  assignment_id bigint,
  assignment_date date,
  old_shift_code text,
  new_shift_code text,
  change_reason text,
  changed_by_name text,
  changed_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);

  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['rota.view_history']);
  END IF;

  RETURN QUERY
  SELECT
    history.id,
    history.rota_assignment_id,
    history.date,
    history.old_shift_code,
    history.new_shift_code,
    history.change_reason,
    history.changed_by_name,
    history.changed_at
  FROM public.rota_assignment_history AS history
  WHERE history.user_id = p_user_id
    AND history.date = p_date
  ORDER BY history.changed_at DESC;
END;
$$;

COMMIT;

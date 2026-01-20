-- ============================================================================
-- Create rota_assignment_history table and audit functions
-- ============================================================================

BEGIN;

-- Create history table
CREATE TABLE IF NOT EXISTS public.rota_assignment_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rota_assignment_id bigint NOT NULL,
  user_id uuid,
  period_non_staff_id uuid REFERENCES public.period_non_staff(id) ON DELETE CASCADE,
  date date NOT NULL,
  old_shift_id bigint,
  old_shift_code text,
  new_shift_id bigint,
  new_shift_code text,
  change_reason text,
  changed_by uuid,
  changed_by_name text,
  changed_at timestamp with time zone DEFAULT now(),
  CONSTRAINT rota_assignment_history_one_assignee CHECK (
    (user_id IS NOT NULL AND period_non_staff_id IS NULL) OR
    (user_id IS NULL AND period_non_staff_id IS NOT NULL)
  )
  -- NO foreign key constraint on rota_assignment_id - we want to preserve history even if assignments are deleted
);

CREATE INDEX IF NOT EXISTS idx_assignment_history_assignment ON public.rota_assignment_history(rota_assignment_id);
CREATE INDEX IF NOT EXISTS idx_assignment_history_user_date ON public.rota_assignment_history(user_id, date) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_assignment_history_non_staff_date ON public.rota_assignment_history(period_non_staff_id, date) WHERE period_non_staff_id IS NOT NULL;
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

  SELECT is_admin INTO v_is_admin
  FROM public.users AS users_table
  WHERE users_table.id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['rota.view_history']);
  END IF;

  RETURN QUERY
  SELECT
    history.id,
    history.rota_assignment_id,
    COALESCE(users_table.name, non_staff_people.name) AS user_name,
    history.date,
    history.old_shift_code,
    history.new_shift_code,
    history.change_reason,
    history.changed_by_name,
    history.changed_at
  FROM public.rota_assignment_history AS history
  LEFT JOIN public.users AS users_table ON users_table.id = history.user_id
  LEFT JOIN public.period_non_staff AS pns ON pns.id = history.period_non_staff_id
  LEFT JOIN public.non_staff_people AS non_staff_people ON non_staff_people.id = pns.non_staff_person_id
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
  rota_assignment_id bigint,
  date date,
  old_shift_code text,
  new_shift_code text,
  change_reason text,
  changed_by_name text,
  changed_at timestamp with time zone,
  override_start_time time without time zone,
  override_end_time time without time zone,
  override_hours numeric,
  override_comment text,
  override_created_at timestamp with time zone
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

  SELECT is_admin INTO v_is_admin
  FROM public.users AS users_table
  WHERE users_table.id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['rota.view_history']);
  END IF;

  RETURN QUERY
  SELECT
    rota_assignment_history.id,
    rota_assignment_history.rota_assignment_id,
    rota_assignment_history.date,
    rota_assignment_history.old_shift_code,
    rota_assignment_history.new_shift_code,
    rota_assignment_history.change_reason,
    rota_assignment_history.changed_by_name,
    rota_assignment_history.changed_at,
    rota_assignment_overrides.override_start_time,
    rota_assignment_overrides.override_end_time,
    rota_assignment_overrides.override_hours,
    rota_assignment_overrides.comment,
    rota_assignment_overrides.created_at
  FROM public.rota_assignment_history
  LEFT JOIN public.rota_assignment_overrides
    ON rota_assignment_overrides.rota_assignment_id = rota_assignment_history.rota_assignment_id
  WHERE (rota_assignment_history.user_id = p_user_id OR rota_assignment_history.period_non_staff_id = p_user_id)
    AND rota_assignment_history.date = p_date
  ORDER BY rota_assignment_history.changed_at DESC;
END;
$$;

COMMIT;

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
  new_shift_id bigint NOT NULL,
  new_shift_code text NOT NULL,
  change_reason text,
  changed_by uuid,
  changed_by_name text,
  changed_at timestamp with time zone DEFAULT now(),
  FOREIGN KEY (rota_assignment_id) REFERENCES public.rota_assignments(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_assignment_history_assignment ON public.rota_assignment_history(rota_assignment_id);
CREATE INDEX IF NOT EXISTS idx_assignment_history_user_date ON public.rota_assignment_history(user_id, date);
CREATE INDEX IF NOT EXISTS idx_assignment_history_changed_at ON public.rota_assignment_history(changed_at DESC);

-- ============================================================================
-- Admin get assignment history (with full audit trail)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_get_assignment_history(p_token uuid, p_assignment_id bigint)
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
    ah.id AS id,
    ah.rota_assignment_id AS assignment_id,
    u.name AS user_name,
    ah.date AS assignment_date,
    ah.old_shift_code AS old_shift_code,
    ah.new_shift_code AS new_shift_code,
    ah.change_reason AS reason,
    ah.changed_by_name AS changed_by_name,
    ah.changed_at AS changed_at
  FROM public.rota_assignment_history ah
  JOIN public.users u ON u.id = ah.user_id
  WHERE ah.rota_assignment_id = p_assignment_id
  ORDER BY ah.changed_at DESC;
END;
$$;

COMMIT;

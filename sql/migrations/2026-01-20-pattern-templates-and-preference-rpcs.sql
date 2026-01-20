-- Add pattern_templates (documentation-only) and preference update RPCs
-- Safe, additive; no behaviour change to existing rota/requests flows.

BEGIN;

-- Pattern templates for clarity (existing code keeps using pattern_definitions/user_patterns)
CREATE TABLE IF NOT EXISTS public.pattern_templates (
  pattern_key text PRIMARY KEY,
  name text NOT NULL,
  cycle_weeks integer NOT NULL,
  weekly_targets integer[] NOT NULL,
  requires_anchor boolean NOT NULL DEFAULT false,
  anchor_type text,
  pattern_type text DEFAULT 'repeating',
  composition_rules text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.touch_pattern_templates_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_pattern_templates_touch ON public.pattern_templates;
CREATE TRIGGER trg_pattern_templates_touch
  BEFORE UPDATE ON public.pattern_templates
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_pattern_templates_updated_at();

-- Seed current known patterns (idempotent upsert by pattern_key)
INSERT INTO public.pattern_templates AS pt
  (pattern_key, name, cycle_weeks, weekly_targets, requires_anchor, anchor_type, pattern_type, composition_rules, notes)
VALUES
  ('two_per_week', '2 shifts/week', 1, ARRAY[2], false, NULL, 'weekly', NULL, 'Exactly 2 shifts per week'),
  ('one_long_one_short', '1 long + 1 short', 1, ARRAY[2], false, NULL, 'composition', '1×12h + 1×8h', 'Contractual blend of long and short'),
  ('three_three_four', '3/3/4 repeating', 3, ARRAY[3,3,4], true, 'week_start_date', 'repeating', NULL, 'Anchored cycle of 3,3,4'),
  ('two_two_three', '2/2/3 repeating', 3, ARRAY[2,2,3], true, 'week_start_date', 'repeating', NULL, 'Anchored cycle of 2,2,3'),
  ('flex_16_in_5w', 'Nurse 5-week flexible (16 shifts: 4×3 + 1×4)', 5, ARRAY[3,3,3,3,3], false, NULL, 'nurse_flexible_16_5w', 'Place one extra shift in any week to reach 16 total', 'Baseline 3/wk; one extra shift somewhere in 5 weeks'),
  ('undefined', 'Undefined', 0, ARRAY[]::integer[], false, NULL, 'undefined', NULL, 'No fixed working pattern')
ON CONFLICT (pattern_key) DO UPDATE
SET name = EXCLUDED.name,
    cycle_weeks = EXCLUDED.cycle_weeks,
    weekly_targets = EXCLUDED.weekly_targets,
    requires_anchor = EXCLUDED.requires_anchor,
    anchor_type = EXCLUDED.anchor_type,
    pattern_type = EXCLUDED.pattern_type,
    composition_rules = EXCLUDED.composition_rules,
    notes = EXCLUDED.notes,
    updated_at = now();

COMMENT ON TABLE public.pattern_templates IS 'Documentation-only pattern catalogue; does not replace pattern_definitions/user_patterns.';


-- ============================================================================
-- Preference update RPCs (self + admin)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_my_preferences(p_token uuid, p_prefs jsonb)
RETURNS TABLE (
  pref_shift_clustering integer,
  pref_night_appetite integer,
  pref_weekend_appetite integer,
  pref_leave_adjacency integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
  v_before jsonb;
  v_after jsonb;
  v_new_shift int;
  v_new_night int;
  v_new_weekend int;
  v_new_leave int;
BEGIN
  v_uid := public.require_session_permissions(p_token, null);
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'permission_denied: invalid session';
  END IF;

  SELECT to_jsonb(u.*) INTO v_before FROM public.users u WHERE u.id = v_uid;

  v_new_shift := COALESCE((p_prefs ->> 'pref_shift_clustering')::int, (SELECT pref_shift_clustering FROM public.users WHERE id = v_uid));
  v_new_night := COALESCE((p_prefs ->> 'pref_night_appetite')::int, (SELECT pref_night_appetite FROM public.users WHERE id = v_uid));
  v_new_weekend := COALESCE((p_prefs ->> 'pref_weekend_appetite')::int, (SELECT pref_weekend_appetite FROM public.users WHERE id = v_uid));
  v_new_leave := COALESCE((p_prefs ->> 'pref_leave_adjacency')::int, (SELECT pref_leave_adjacency FROM public.users WHERE id = v_uid));

  IF NOT (v_new_shift BETWEEN 1 AND 5) THEN RAISE EXCEPTION 'pref_shift_clustering must be 1-5'; END IF;
  IF NOT (v_new_night BETWEEN 1 AND 5) THEN RAISE EXCEPTION 'pref_night_appetite must be 1-5'; END IF;
  IF NOT (v_new_weekend BETWEEN 1 AND 5) THEN RAISE EXCEPTION 'pref_weekend_appetite must be 1-5'; END IF;
  IF NOT (v_new_leave BETWEEN 1 AND 5) THEN RAISE EXCEPTION 'pref_leave_adjacency must be 1-5'; END IF;

  UPDATE public.users
  SET pref_shift_clustering = v_new_shift,
      pref_night_appetite = v_new_night,
      pref_weekend_appetite = v_new_weekend,
      pref_leave_adjacency = v_new_leave
  WHERE id = v_uid;

  SELECT to_jsonb(u.*) INTO v_after FROM public.users u WHERE u.id = v_uid;

  INSERT INTO public.audit_logs (user_id, impersonator_user_id, action, resource_type, resource_id, target_user_id, old_values, new_values, status, created_at)
  VALUES (v_uid, NULL, 'user.preferences.update', 'user', v_uid, v_uid, v_before, v_after, 'success', now());

  RETURN QUERY
  SELECT v_new_shift, v_new_night, v_new_weekend, v_new_leave;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_user_preferences(p_token uuid, p_user_id uuid, p_prefs jsonb)
RETURNS TABLE (
  pref_shift_clustering integer,
  pref_night_appetite integer,
  pref_weekend_appetite integer,
  pref_leave_adjacency integer,
  can_be_in_charge_day boolean,
  can_be_in_charge_night boolean,
  cannot_be_second_rn_day boolean,
  cannot_be_second_rn_night boolean,
  can_work_nights boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_actor uuid;
  v_is_admin boolean;
  v_before jsonb;
  v_after jsonb;
  v_new_shift int;
  v_new_night int;
  v_new_weekend int;
  v_new_leave int;
  v_c_charge_day boolean;
  v_c_charge_night boolean;
  v_c_second_day boolean;
  v_c_second_night boolean;
  v_can_work_nights boolean;
BEGIN
  v_actor := public.require_session_permissions(p_token, null);
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'permission_denied: invalid session';
  END IF;

  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_actor;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['users.edit']);
  END IF;

  SELECT to_jsonb(u.*) INTO v_before FROM public.users u WHERE u.id = p_user_id;

  v_new_shift := COALESCE((p_prefs ->> 'pref_shift_clustering')::int, (SELECT pref_shift_clustering FROM public.users WHERE id = p_user_id));
  v_new_night := COALESCE((p_prefs ->> 'pref_night_appetite')::int, (SELECT pref_night_appetite FROM public.users WHERE id = p_user_id));
  v_new_weekend := COALESCE((p_prefs ->> 'pref_weekend_appetite')::int, (SELECT pref_weekend_appetite FROM public.users WHERE id = p_user_id));
  v_new_leave := COALESCE((p_prefs ->> 'pref_leave_adjacency')::int, (SELECT pref_leave_adjacency FROM public.users WHERE id = p_user_id));

  v_c_charge_day := COALESCE((p_prefs ->> 'can_be_in_charge_day')::boolean, (SELECT can_be_in_charge_day FROM public.users WHERE id = p_user_id));
  v_c_charge_night := COALESCE((p_prefs ->> 'can_be_in_charge_night')::boolean, (SELECT can_be_in_charge_night FROM public.users WHERE id = p_user_id));
  v_c_second_day := COALESCE((p_prefs ->> 'cannot_be_second_rn_day')::boolean, (SELECT cannot_be_second_rn_day FROM public.users WHERE id = p_user_id));
  v_c_second_night := COALESCE((p_prefs ->> 'cannot_be_second_rn_night')::boolean, (SELECT cannot_be_second_rn_night FROM public.users WHERE id = p_user_id));
  v_can_work_nights := COALESCE((p_prefs ->> 'can_work_nights')::boolean, (SELECT can_work_nights FROM public.users WHERE id = p_user_id));

  IF NOT (v_new_shift BETWEEN 1 AND 5) THEN RAISE EXCEPTION 'pref_shift_clustering must be 1-5'; END IF;
  IF NOT (v_new_night BETWEEN 1 AND 5) THEN RAISE EXCEPTION 'pref_night_appetite must be 1-5'; END IF;
  IF NOT (v_new_weekend BETWEEN 1 AND 5) THEN RAISE EXCEPTION 'pref_weekend_appetite must be 1-5'; END IF;
  IF NOT (v_new_leave BETWEEN 1 AND 5) THEN RAISE EXCEPTION 'pref_leave_adjacency must be 1-5'; END IF;

  UPDATE public.users
  SET pref_shift_clustering = v_new_shift,
      pref_night_appetite = v_new_night,
      pref_weekend_appetite = v_new_weekend,
      pref_leave_adjacency = v_new_leave,
      can_be_in_charge_day = v_c_charge_day,
      can_be_in_charge_night = v_c_charge_night,
      cannot_be_second_rn_day = v_c_second_day,
      cannot_be_second_rn_night = v_c_second_night,
      can_work_nights = v_can_work_nights
  WHERE id = p_user_id;

  SELECT to_jsonb(u.*) INTO v_after FROM public.users u WHERE u.id = p_user_id;

  INSERT INTO public.audit_logs (user_id, impersonator_user_id, action, resource_type, resource_id, target_user_id, old_values, new_values, status, created_at)
  VALUES (v_actor, NULL, 'admin.user.preferences.update', 'user', p_user_id, p_user_id, v_before, v_after, 'success', now());

  RETURN QUERY
  SELECT v_new_shift, v_new_night, v_new_weekend, v_new_leave, v_c_charge_day, v_c_charge_night, v_c_second_day, v_c_second_night, v_can_work_nights;
END;
$$;

COMMIT;

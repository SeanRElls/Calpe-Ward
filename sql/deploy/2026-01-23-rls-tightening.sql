BEGIN;

-- Enable RLS on core tables that were previously open.
ALTER TABLE public.admin_pins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_holidays ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_rate_limiting ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.non_staff_people ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notice_targets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operation_rate_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pattern_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.period_non_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permission_group_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permission_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.planned_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rota_assignment_audits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rota_assignment_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rota_assignment_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rota_assignment_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rota_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rota_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shift_catalogue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shift_eligibility ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.swap_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.swap_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_patterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_permission_groups ENABLE ROW LEVEL SECURITY;

-- Drop overly permissive policies.
DROP POLICY IF EXISTS "admins_full_access" ON public.users;
DROP POLICY IF EXISTS "users_read_active" ON public.users;
DROP POLICY IF EXISTS "users_read_active_staff" ON public.users;
DROP POLICY IF EXISTS "users_read_self" ON public.users;

DROP POLICY IF EXISTS "admin can read notices" ON public.notices;
DROP POLICY IF EXISTS "notices no direct" ON public.notices;

DROP POLICY IF EXISTS "public read roles" ON public.roles;
DROP POLICY IF EXISTS "roles_public_read" ON public.roles;

DROP POLICY IF EXISTS "public read rota_dates" ON public.rota_dates;
DROP POLICY IF EXISTS "public_read_rota_dates" ON public.rota_dates;
DROP POLICY IF EXISTS "rota_dates_public_read" ON public.rota_dates;
DROP POLICY IF EXISTS "rota_dates_read" ON public.rota_dates;

DROP POLICY IF EXISTS "public read rota_weeks" ON public.rota_weeks;
DROP POLICY IF EXISTS "public_read_rota_weeks" ON public.rota_weeks;
DROP POLICY IF EXISTS "rota_weeks_public_read" ON public.rota_weeks;
DROP POLICY IF EXISTS "rota_weeks_read" ON public.rota_weeks;

DROP POLICY IF EXISTS "public read rota_periods" ON public.rota_periods;
DROP POLICY IF EXISTS "public_read_rota_periods" ON public.rota_periods;
DROP POLICY IF EXISTS "rota_periods_public_read" ON public.rota_periods;
DROP POLICY IF EXISTS "rota_periods_read" ON public.rota_periods;

DROP POLICY IF EXISTS "Can delete overrides" ON public.rota_assignment_overrides;
DROP POLICY IF EXISTS "Can insert overrides" ON public.rota_assignment_overrides;
DROP POLICY IF EXISTS "Can select overrides" ON public.rota_assignment_overrides;
DROP POLICY IF EXISTS "Can update overrides" ON public.rota_assignment_overrides;

DROP POLICY IF EXISTS "Can delete own comments" ON public.rota_assignment_comments;
DROP POLICY IF EXISTS "Can insert comments" ON public.rota_assignment_comments;
DROP POLICY IF EXISTS "Can select own and public comments" ON public.rota_assignment_comments;
DROP POLICY IF EXISTS "Can update own comments" ON public.rota_assignment_comments;

-- Users: direct read only for self/admin; no direct writes.
CREATE POLICY "users_read_self" ON public.users
FOR SELECT
USING (auth.uid() = id);

CREATE POLICY "users_read_admin" ON public.users
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid()
      AND u.is_admin = true
  )
);

CREATE POLICY "users_no_insert" ON public.users
FOR INSERT
WITH CHECK (false);

CREATE POLICY "users_no_update" ON public.users
FOR UPDATE
USING (false)
WITH CHECK (false);

CREATE POLICY "users_no_delete" ON public.users
FOR DELETE
USING (false);

-- Notices: no direct access (RPC-only).
CREATE POLICY "notices_no_direct" ON public.notices
FOR ALL
USING (false)
WITH CHECK (false);

-- Roles: no direct access (RPC-only).
CREATE POLICY "roles_no_direct" ON public.roles
FOR ALL
USING (false)
WITH CHECK (false);

-- Rota dates/weeks/periods: no direct access (RPC-only).
CREATE POLICY "rota_dates_no_direct" ON public.rota_dates
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "rota_weeks_no_direct" ON public.rota_weeks
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "rota_periods_no_direct" ON public.rota_periods
FOR ALL
USING (false)
WITH CHECK (false);

-- Assignment overrides/comments: no direct access (RPC-only).
CREATE POLICY "rota_assignment_overrides_no_direct" ON public.rota_assignment_overrides
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "rota_assignment_comments_no_direct" ON public.rota_assignment_comments
FOR ALL
USING (false)
WITH CHECK (false);

-- Deny direct access for newly RLS-enabled tables (RPC-only).
CREATE POLICY "admin_pins_no_direct" ON public.admin_pins
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "app_settings_no_direct" ON public.app_settings
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "bank_holidays_no_direct" ON public.bank_holidays
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "login_audit_no_direct" ON public.login_audit
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "login_rate_limiting_no_direct" ON public.login_rate_limiting
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "non_staff_people_no_direct" ON public.non_staff_people
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "notice_targets_no_direct" ON public.notice_targets
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "notifications_no_direct" ON public.notifications
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "operation_rate_limits_no_direct" ON public.operation_rate_limits
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "pattern_templates_no_direct" ON public.pattern_templates
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "period_non_staff_no_direct" ON public.period_non_staff
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "permission_group_permissions_no_direct" ON public.permission_group_permissions
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "permission_groups_no_direct" ON public.permission_groups
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "permissions_no_direct" ON public.permissions
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "planned_assignments_no_direct" ON public.planned_assignments
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "rota_assignment_audits_no_direct" ON public.rota_assignment_audits
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "rota_assignment_history_no_direct" ON public.rota_assignment_history
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "rota_assignments_no_direct" ON public.rota_assignments
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "sessions_no_direct" ON public.sessions
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "shift_catalogue_no_direct" ON public.shift_catalogue
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "shift_eligibility_no_direct" ON public.shift_eligibility
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "shifts_no_direct" ON public.shifts
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "swap_executions_no_direct" ON public.swap_executions
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "swap_requests_no_direct" ON public.swap_requests
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "user_patterns_no_direct" ON public.user_patterns
FOR ALL
USING (false)
WITH CHECK (false);

CREATE POLICY "user_permission_groups_no_direct" ON public.user_permission_groups
FOR ALL
USING (false)
WITH CHECK (false);

COMMIT;

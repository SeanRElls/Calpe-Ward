-- =====================================================
-- NON-STAFF & MENTOR ENABLEMENT FEATURE
-- Deployment Script - Run this to enable non-staff functionality
-- =====================================================
-- This script:
-- 1. Creates non_staff_people and period_non_staff tables
-- 2. Modifies rota_assignments to support non-staff
-- 3. Adds RPC functions for managing non-staff
-- 4. Sets up permission helpers for mentor gating
-- =====================================================

BEGIN;

-- =====================================================
-- STEP 1: Create non_staff_people table
-- =====================================================
CREATE TABLE IF NOT EXISTS public.non_staff_people (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('student', 'bank', 'agency')),
    role_group TEXT,
    notes TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    
    CONSTRAINT non_staff_people_name_unique UNIQUE (name)
);

CREATE INDEX IF NOT EXISTS idx_non_staff_people_category 
    ON public.non_staff_people(category);
CREATE INDEX IF NOT EXISTS idx_non_staff_people_active 
    ON public.non_staff_people(is_active);

-- Auto-update trigger for updated_at
CREATE OR REPLACE FUNCTION public.update_non_staff_people_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_non_staff_people_updated_at ON public.non_staff_people;
CREATE TRIGGER trg_non_staff_people_updated_at
    BEFORE UPDATE ON public.non_staff_people
    FOR EACH ROW
    EXECUTE FUNCTION public.update_non_staff_people_updated_at();

COMMENT ON TABLE public.non_staff_people IS 'Reusable profiles for non-staff (students, bank, agency)';
COMMENT ON COLUMN public.non_staff_people.category IS 'student, bank, or agency';
COMMENT ON COLUMN public.non_staff_people.role_group IS 'NULL for students; staff_nurse or nursing_assistant for bank/agency';
COMMENT ON COLUMN public.non_staff_people.is_active IS 'Soft delete flag - inactive people cannot be added to new periods';

-- Ensure role_group NULLability and category/role_group consistency (idempotent)
ALTER TABLE public.non_staff_people
    ALTER COLUMN role_group DROP NOT NULL;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'non_staff_people_role_group_check'
    ) THEN
        ALTER TABLE public.non_staff_people DROP CONSTRAINT non_staff_people_role_group_check;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'non_staff_people_category_rolegroup_check'
    ) THEN
        ALTER TABLE public.non_staff_people
        ADD CONSTRAINT non_staff_people_category_rolegroup_check
        CHECK (
          (category = 'student' AND role_group IS NULL)
          OR (category IN ('bank','agency') AND role_group IN ('staff_nurse','nursing_assistant'))
        );
    END IF;
END $$;

-- =====================================================
-- STEP 2: Create period_non_staff table
-- =====================================================
CREATE TABLE IF NOT EXISTS public.period_non_staff (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    period_id UUID NOT NULL REFERENCES public.rota_periods(id) ON DELETE CASCADE,
    non_staff_person_id UUID NOT NULL REFERENCES public.non_staff_people(id) ON DELETE CASCADE,
    
    display_order INTEGER NOT NULL DEFAULT 9999,
    counts_towards_staffing BOOLEAN NOT NULL DEFAULT FALSE,
    
    added_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    added_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    removed_at TIMESTAMP WITH TIME ZONE,
    removed_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    
    CONSTRAINT period_non_staff_unique UNIQUE (period_id, non_staff_person_id, removed_at),
    CONSTRAINT period_non_staff_active_unique 
        EXCLUDE USING btree (period_id WITH =, non_staff_person_id WITH =) 
        WHERE (removed_at IS NULL)
);

CREATE INDEX IF NOT EXISTS idx_period_non_staff_period 
    ON public.period_non_staff(period_id) WHERE removed_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_period_non_staff_person 
    ON public.period_non_staff(non_staff_person_id);
CREATE INDEX IF NOT EXISTS idx_period_non_staff_active 
    ON public.period_non_staff(period_id, removed_at);

COMMENT ON TABLE public.period_non_staff IS 'Links non-staff people to specific periods for rota display';
COMMENT ON COLUMN public.period_non_staff.counts_towards_staffing IS 'TRUE for bank/agency, FALSE for students';
COMMENT ON COLUMN public.period_non_staff.display_order IS 'Sort order (9999 keeps non-staff at bottom of their role group)';
COMMENT ON COLUMN public.period_non_staff.removed_at IS 'Soft delete - when non-staff person removed from period';

-- =====================================================
-- STEP 3: Modify rota_assignments table
-- =====================================================
DO $$
BEGIN
    -- Add period_non_staff_id column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
            AND table_name = 'rota_assignments' 
            AND column_name = 'period_non_staff_id'
    ) THEN
        ALTER TABLE public.rota_assignments 
            ADD COLUMN period_non_staff_id UUID 
            REFERENCES public.period_non_staff(id) ON DELETE CASCADE;
    END IF;
END $$;

-- Make user_id nullable
ALTER TABLE public.rota_assignments 
    ALTER COLUMN user_id DROP NOT NULL;

-- Add check constraint (exactly one assignee)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'rota_assignments_one_assignee'
    ) THEN
        ALTER TABLE public.rota_assignments 
            ADD CONSTRAINT rota_assignments_one_assignee 
            CHECK (
                (user_id IS NOT NULL AND period_non_staff_id IS NULL) OR
                (user_id IS NULL AND period_non_staff_id IS NOT NULL)
            );
    END IF;
END $$;

-- Drop old unique constraint and add new one
ALTER TABLE public.rota_assignments 
    DROP CONSTRAINT IF EXISTS rota_assignments_user_id_date_status_key;

ALTER TABLE public.rota_assignments 
    DROP CONSTRAINT IF EXISTS rota_assignments_assignee_date_status_unique;

ALTER TABLE public.rota_assignments 
    ADD CONSTRAINT rota_assignments_assignee_date_status_unique 
    UNIQUE (user_id, period_non_staff_id, date, status);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_rota_assignments_period_non_staff 
    ON public.rota_assignments(period_non_staff_id) 
    WHERE period_non_staff_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_rota_assignments_user_id 
    ON public.rota_assignments(user_id) 
    WHERE user_id IS NOT NULL;

COMMENT ON COLUMN public.rota_assignments.period_non_staff_id IS 'FK to period_non_staff - exactly one of user_id or period_non_staff_id must be set';

-- =====================================================
-- STEP 3B: Update rota_assignment_history to track non-staff
-- =====================================================
ALTER TABLE public.rota_assignment_history
    ADD COLUMN IF NOT EXISTS period_non_staff_id UUID REFERENCES public.period_non_staff(id) ON DELETE CASCADE;

ALTER TABLE public.rota_assignment_history
    ALTER COLUMN user_id DROP NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'rota_assignment_history_one_assignee'
    ) THEN
        ALTER TABLE public.rota_assignment_history
            ADD CONSTRAINT rota_assignment_history_one_assignee
            CHECK (
                (user_id IS NOT NULL AND period_non_staff_id IS NULL)
                OR (user_id IS NULL AND period_non_staff_id IS NOT NULL)
            );
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_rah_period_non_staff
    ON public.rota_assignment_history(period_non_staff_id)
    WHERE period_non_staff_id IS NOT NULL;

-- =====================================================
-- STEP 4: RPC Functions
-- =====================================================

-- Helper: Check if user can edit non-staff shift
CREATE OR REPLACE FUNCTION public.can_edit_non_staff_shift(
    p_user_id UUID,
    p_period_non_staff_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_is_admin BOOLEAN;
    v_is_mentor BOOLEAN;
    v_category TEXT;
BEGIN
    SELECT is_admin INTO v_is_admin
    FROM public.users
    WHERE id = p_user_id;
    
    IF v_is_admin THEN
        RETURN TRUE;
    END IF;
    
    SELECT EXISTS(
        SELECT 1 
        FROM public.user_permission_groups upg
        JOIN public.permission_groups pg ON upg.group_id = pg.id
        WHERE upg.user_id = p_user_id 
            AND pg.name = 'Mentor'
    ) INTO v_is_mentor;
    
    SELECT nsp.category INTO v_category
    FROM public.period_non_staff pns
    JOIN public.non_staff_people nsp ON pns.non_staff_person_id = nsp.id
    WHERE pns.id = p_period_non_staff_id;
    
    IF v_is_mentor AND v_category = 'student' THEN
        RETURN TRUE;
    END IF;
    
    RETURN FALSE;
END;
$$;

-- RPC: Add non-staff person profile
CREATE OR REPLACE FUNCTION public.rpc_add_non_staff_person(
    p_token UUID,
    p_name TEXT,
    p_category TEXT,
    p_role_group TEXT,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_is_admin BOOLEAN;
    v_is_mentor BOOLEAN;
    v_new_id UUID;
BEGIN
    SELECT user_id INTO v_user_id
    FROM public.sessions
    WHERE token = p_token
        AND expires_at > NOW()
        AND revoked_at IS NULL;
    
    IF v_user_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Invalid or expired session');
    END IF;
    
    SELECT is_admin INTO v_is_admin
    FROM public.users
    WHERE id = v_user_id;
    
    SELECT EXISTS(
        SELECT 1 
        FROM public.user_permission_groups upg
        JOIN public.permission_groups pg ON upg.group_id = pg.id
        WHERE upg.user_id = v_user_id 
            AND pg.name = 'Mentor'
    ) INTO v_is_mentor;
    
    IF p_category NOT IN ('student', 'bank', 'agency') THEN
        RETURN json_build_object('success', false, 'error', 'Invalid category');
    END IF;
    
    -- Validate role group depending on category
    IF p_category = 'student' THEN
        -- Students must not have a role_group
        p_role_group := NULL;
    ELSIF p_category IN ('bank','agency') THEN
        IF p_role_group NOT IN ('staff_nurse','nursing_assistant') THEN
            RETURN json_build_object('success', false, 'error', 'Invalid role group');
        END IF;
    END IF;
    
    IF p_category IN ('bank', 'agency') AND NOT v_is_admin THEN
        RETURN json_build_object('success', false, 'error', 'Only admins can add bank/agency staff');
    END IF;
    
    IF p_category = 'student' AND NOT (v_is_admin OR v_is_mentor) THEN
        RETURN json_build_object('success', false, 'error', 'Requires mentor or admin permission');
    END IF;
    
    INSERT INTO public.non_staff_people (
        name, category, role_group, notes, created_by, updated_by
    )
    VALUES (
        p_name, p_category, p_role_group, p_notes, v_user_id, v_user_id
    )
    RETURNING id INTO v_new_id;
    
    INSERT INTO public.audit_logs (
        user_id, action, resource_type, resource_id, 
        new_values, metadata
    )
    VALUES (
        v_user_id, 'create', 'non_staff_person', v_new_id,
        json_build_object(
            'name', p_name,
            'category', p_category,
            'role_group', p_role_group
        ),
        json_build_object('notes', p_notes)
    );
    
    RETURN json_build_object(
        'success', true, 
        'id', v_new_id,
        'message', 'Non-staff person created successfully'
    );
END;
$$;

-- RPC: Add non-staff to period
CREATE OR REPLACE FUNCTION public.rpc_add_non_staff_to_period(
    p_token UUID,
    p_period_id UUID,
    p_non_staff_person_id UUID,
    p_counts_towards_staffing BOOLEAN DEFAULT FALSE,
    p_display_order INTEGER DEFAULT 9999
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_is_admin BOOLEAN;
    v_is_mentor BOOLEAN;
    v_category TEXT;
    v_new_id UUID;
BEGIN
    SELECT user_id INTO v_user_id
    FROM public.sessions
    WHERE token = p_token
        AND expires_at > NOW()
        AND revoked_at IS NULL;
    
    IF v_user_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Invalid or expired session');
    END IF;
    
    SELECT is_admin INTO v_is_admin
    FROM public.users
    WHERE id = v_user_id;
    
    SELECT EXISTS(
        SELECT 1 
        FROM public.user_permission_groups upg
        JOIN public.permission_groups pg ON upg.group_id = pg.id
        WHERE upg.user_id = v_user_id 
            AND pg.name = 'Mentor'
    ) INTO v_is_mentor;
    
    SELECT category INTO v_category
    FROM public.non_staff_people
    WHERE id = p_non_staff_person_id AND is_active = TRUE;
    
    IF v_category IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Non-staff person not found or inactive');
    END IF;
    
    IF v_category IN ('bank', 'agency') AND NOT v_is_admin THEN
        RETURN json_build_object('success', false, 'error', 'Only admins can add bank/agency to periods');
    END IF;
    
    IF v_category = 'student' AND NOT (v_is_admin OR v_is_mentor) THEN
        RETURN json_build_object('success', false, 'error', 'Requires mentor or admin permission');
    END IF;
    
    IF EXISTS(
        SELECT 1 FROM public.period_non_staff
        WHERE period_id = p_period_id
            AND non_staff_person_id = p_non_staff_person_id
            AND removed_at IS NULL
    ) THEN
        RETURN json_build_object('success', false, 'error', 'Already added to this period');
    END IF;
    
    INSERT INTO public.period_non_staff (
        period_id, non_staff_person_id, 
        counts_towards_staffing, display_order,
        added_by
    )
    VALUES (
        p_period_id, p_non_staff_person_id,
        -- Enforce staffing count rule: bank/agency count, students do not
        CASE WHEN v_category = 'agency' THEN TRUE
             WHEN v_category = 'student' THEN FALSE
             ELSE p_counts_towards_staffing END,
        p_display_order,
        v_user_id
    
    RETURNING id INTO v_new_id;
    
    INSERT INTO public.audit_logs (
        user_id, action, resource_type, resource_id,
        new_values
    )
    VALUES (
        v_user_id, 'add_to_period', 'period_non_staff', v_new_id,
        json_build_object(
            'period_id', p_period_id,
            'non_staff_person_id', p_non_staff_person_id,
            'category', v_category
        )
    );
    
    RETURN json_build_object(
        'success', true,
        'id', v_new_id,
        'message', 'Non-staff added to period successfully'
    );
END;
$$;

-- RPC: Get period non-staff
CREATE OR REPLACE FUNCTION public.rpc_get_period_non_staff(
    p_token UUID,
    p_period_id UUID
)
RETURNS TABLE (
    id UUID,
    period_non_staff_id UUID,
    name TEXT,
    category TEXT,
    role_group TEXT,
    counts_towards_staffing BOOLEAN,
    display_order INTEGER,
    notes TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    SELECT user_id INTO v_user_id
    FROM public.sessions
    WHERE token = p_token
        AND expires_at > NOW()
        AND revoked_at IS NULL;
    
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Invalid or expired session';
    END IF;
    
    RETURN QUERY
    SELECT 
        nsp.id AS id,
        pns.id AS period_non_staff_id,
        nsp.name,
        nsp.category,
        nsp.role_group,
        pns.counts_towards_staffing,
        pns.display_order,
        nsp.notes
    FROM public.period_non_staff pns
    JOIN public.non_staff_people nsp ON pns.non_staff_person_id = nsp.id
    WHERE pns.period_id = p_period_id
        AND pns.removed_at IS NULL
        AND nsp.is_active = TRUE
    ORDER BY pns.display_order, nsp.name;
END;
$$;

-- RPC: List non-staff profiles (with mentor/admin gating)
CREATE OR REPLACE FUNCTION public.rpc_list_non_staff_people(
    p_token UUID,
    p_category TEXT DEFAULT NULL,
    p_role_group TEXT DEFAULT NULL,
    p_query TEXT DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    name TEXT,
    category TEXT,
    role_group TEXT,
    notes TEXT,
    is_active BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_is_admin BOOLEAN;
    v_is_mentor BOOLEAN;
BEGIN
    SELECT user_id INTO v_user_id
    FROM public.sessions
    WHERE token = p_token
      AND expires_at > NOW()
      AND revoked_at IS NULL;

    IF v_user_id IS NULL THEN
        RETURN;
    END IF;

    SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_user_id;
    SELECT EXISTS(
        SELECT 1 FROM public.user_permission_groups upg
        JOIN public.permission_groups pg ON upg.group_id = pg.id
        WHERE upg.user_id = v_user_id AND pg.name = 'Mentor'
    ) INTO v_is_mentor;

    RETURN QUERY
    SELECT
        nsp.id, nsp.name, nsp.category, nsp.role_group, nsp.notes, nsp.is_active
    FROM public.non_staff_people nsp
    WHERE nsp.is_active = TRUE
            AND (p_role_group IS NULL OR nsp.role_group = p_role_group)
      AND (p_category IS NULL OR nsp.category = p_category)
      AND (p_query IS NULL OR nsp.name ILIKE '%' || p_query || '%')
      AND (
          v_is_admin OR (v_is_mentor AND nsp.category = 'student')
      )
    ORDER BY nsp.name;
END;
$$;

COMMIT;

-- =====================================================
-- DEPLOYMENT COMPLETE
-- Next steps:
-- 1. Update UI to fetch and display non-staff
-- 2. Add mentor gating to context menu
-- 3. Update staffing calculations
-- =====================================================
-- =====================================================
-- ADDITIONAL ADMIN RPCs (Profiles Management)
-- Safe to re-run; functions are CREATE OR REPLACE.
-- =====================================================

BEGIN;

-- Admin list (optionally include inactive). Admin-only.
CREATE OR REPLACE FUNCTION public.rpc_admin_list_non_staff_people(
    p_token UUID,
    p_include_inactive BOOLEAN DEFAULT FALSE,
    p_category TEXT DEFAULT NULL,
    p_role_group TEXT DEFAULT NULL,
    p_query TEXT DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    name TEXT,
    category TEXT,
    role_group TEXT,
    notes TEXT,
    is_active BOOLEAN,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_is_admin BOOLEAN;
BEGIN
    SELECT user_id INTO v_user_id
    FROM public.sessions
    WHERE token = p_token
      AND expires_at > NOW()
      AND revoked_at IS NULL;

    IF v_user_id IS NULL THEN
        RETURN;
    END IF;

    SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_user_id;
    IF NOT COALESCE(v_is_admin, FALSE) THEN
        RETURN; -- admin only
    END IF;

    RETURN QUERY
    SELECT nsp.id, nsp.name, nsp.category, nsp.role_group, nsp.notes, nsp.is_active, nsp.created_at, nsp.updated_at
    FROM public.non_staff_people nsp
    WHERE (p_role_group IS NULL OR nsp.role_group = p_role_group)
      AND (p_category IS NULL OR nsp.category = p_category)
      AND (p_query IS NULL OR nsp.name ILIKE '%' || p_query || '%')
      AND (p_include_inactive OR nsp.is_active = TRUE)
    ORDER BY nsp.is_active DESC, nsp.name ASC;
END;
$$;

-- Admin update profile (name/category/role_group/notes). Admin-only.
CREATE OR REPLACE FUNCTION public.rpc_update_non_staff_person(
    p_token UUID,
    p_id UUID,
    p_name TEXT,
    p_category TEXT,
    p_role_group TEXT,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_is_admin BOOLEAN;
    v_prev RECORD;
BEGIN
    SELECT user_id INTO v_user_id
    FROM public.sessions
    WHERE token = p_token
      AND expires_at > NOW()
      AND revoked_at IS NULL;

    IF v_user_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Invalid or expired session');
    END IF;

    SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_user_id;
    IF NOT COALESCE(v_is_admin, FALSE) THEN
        RETURN json_build_object('success', false, 'error', 'Admin only');
    END IF;

    IF p_category NOT IN ('student','bank','agency') THEN
        RETURN json_build_object('success', false, 'error', 'Invalid category');
    END IF;
    IF p_role_group NOT IN ('staff_nurse','nursing_assistant') THEN
        RETURN json_build_object('success', false, 'error', 'Invalid role group');
    END IF;

    SELECT * INTO v_prev FROM public.non_staff_people WHERE id = p_id;
    IF v_prev IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
    END IF;

    UPDATE public.non_staff_people
    SET name = p_name,
        category = p_category,
        role_group = p_role_group,
        notes = p_notes,
        updated_by = v_user_id,
        updated_at = NOW()
    WHERE id = p_id;

    INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, old_values, new_values)
    VALUES (
      v_user_id,
      'update',
      'non_staff_person',
      p_id,
      to_jsonb(v_prev),
      json_build_object('name', p_name, 'category', p_category, 'role_group', p_role_group, 'notes', p_notes)
    );

    RETURN json_build_object('success', true, 'message', 'Profile updated');
END;
$$;

-- Admin toggle active flag. Admin-only.
CREATE OR REPLACE FUNCTION public.rpc_set_non_staff_active(
    p_token UUID,
    p_id UUID,
    p_active BOOLEAN
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_is_admin BOOLEAN;
    v_prev RECORD;
BEGIN
    SELECT user_id INTO v_user_id
    FROM public.sessions
    WHERE token = p_token
      AND expires_at > NOW()
      AND revoked_at IS NULL;

    IF v_user_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Invalid or expired session');
    END IF;

    SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_user_id;
    IF NOT COALESCE(v_is_admin, FALSE) THEN
        RETURN json_build_object('success', false, 'error', 'Admin only');
    END IF;

    SELECT * INTO v_prev FROM public.non_staff_people WHERE id = p_id;
    IF v_prev IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
    END IF;

    UPDATE public.non_staff_people
    SET is_active = p_active,
        updated_by = v_user_id,
        updated_at = NOW()
    WHERE id = p_id;

    INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, old_values, new_values)
    VALUES (
      v_user_id,
      CASE WHEN p_active THEN 'reactivate' ELSE 'deactivate' END,
      'non_staff_person',
      p_id,
      to_jsonb(v_prev),
      json_build_object('is_active', p_active)
    );

    RETURN json_build_object('success', true, 'message', 'Active status updated');
END;
$$;

COMMIT;


-- ADD MISSING FUNCTION: rpc_remove_non_staff_from_period
-- This function was called by the JavaScript but never created

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_remove_non_staff_from_period(
    p_token UUID,
    p_period_non_staff_id UUID
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
    v_period_id UUID;
    v_non_staff_person_id UUID;
BEGIN
    -- Validate session
    SELECT user_id INTO v_user_id
    FROM public.sessions
    WHERE token = p_token
        AND expires_at > NOW()
        AND revoked_at IS NULL;
    
    IF v_user_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Invalid or expired session');
    END IF;
    
    -- Check admin status
    SELECT is_admin INTO v_is_admin
    FROM public.users
    WHERE id = v_user_id;
    
    -- Check mentor status
    SELECT EXISTS(
        SELECT 1 
        FROM public.user_permission_groups upg
        JOIN public.permission_groups pg ON upg.group_id = pg.id
        WHERE upg.user_id = v_user_id 
            AND pg.name = 'Mentor'
    ) INTO v_is_mentor;
    
    -- Get the non-staff person details
    SELECT pns.period_id, pns.non_staff_person_id, nsp.category
    INTO v_period_id, v_non_staff_person_id, v_category
    FROM public.period_non_staff pns
    JOIN public.non_staff_people nsp ON pns.non_staff_person_id = nsp.id
    WHERE pns.id = p_period_non_staff_id
        AND pns.removed_at IS NULL;
    
    IF v_category IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Period non-staff record not found or already removed');
    END IF;
    
    -- Check permissions: admin always allowed, mentor only for students
    IF NOT v_is_admin AND NOT (v_is_mentor AND v_category = 'student') THEN
        RETURN json_build_object('success', false, 'error', 'Insufficient permissions to remove this non-staff member');
    END IF;
    
    -- Soft delete by setting removed_at and removed_by
    UPDATE public.period_non_staff
    SET removed_at = NOW(),
        removed_by = v_user_id
    WHERE id = p_period_non_staff_id;
    
    -- Log the removal
    INSERT INTO public.audit_logs (
        user_id, action, resource_type, resource_id,
        old_values
    )
    VALUES (
        v_user_id, 'remove_from_period', 'period_non_staff', p_period_non_staff_id,
        json_build_object(
            'period_id', v_period_id,
            'non_staff_person_id', v_non_staff_person_id,
            'category', v_category
        )
    );
    
    RETURN json_build_object(
        'success', true,
        'message', 'Non-staff member removed from period'
    );
END;
$$;

COMMIT;

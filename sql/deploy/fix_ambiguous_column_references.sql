-- FIX: Ensure all column references are fully qualified in non-staff RPCs
-- This addresses potential ambiguous column reference errors

BEGIN;

-- Fix rpc_get_period_non_staff to fully qualify the WHERE clause
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
        nsp.id,
        pns.id,
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

COMMIT;

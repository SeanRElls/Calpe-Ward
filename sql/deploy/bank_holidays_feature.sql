-- =====================================================
-- BANK HOLIDAYS FEATURE
-- Deployment Script - Add bank holidays per year
-- =====================================================

BEGIN;

-- Create bank_holidays table
CREATE TABLE IF NOT EXISTS public.bank_holidays (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    year INTEGER NOT NULL,
    holiday_date DATE NOT NULL,
    name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    CONSTRAINT bank_holidays_unique_date UNIQUE (year, holiday_date)
);

CREATE INDEX IF NOT EXISTS idx_bank_holidays_year ON public.bank_holidays(year);
CREATE INDEX IF NOT EXISTS idx_bank_holidays_date ON public.bank_holidays(holiday_date);
CREATE INDEX IF NOT EXISTS idx_bank_holidays_active ON public.bank_holidays(is_active);

COMMENT ON TABLE public.bank_holidays IS 'Bank holidays per year for the rota';
COMMENT ON COLUMN public.bank_holidays.year IS 'Year of the bank holiday (e.g., 2026)';
COMMENT ON COLUMN public.bank_holidays.holiday_date IS 'The date of the bank holiday';
COMMENT ON COLUMN public.bank_holidays.name IS 'Name of the bank holiday (e.g., Christmas Day, New Year)';

-- RPC to list bank holidays by year
CREATE OR REPLACE FUNCTION public.rpc_list_bank_holidays(p_year INTEGER DEFAULT NULL)
RETURNS TABLE (id UUID, year INTEGER, holiday_date DATE, name TEXT, is_active BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT bh.id, bh.year, bh.holiday_date, bh.name, bh.is_active
  FROM public.bank_holidays bh
  WHERE (p_year IS NULL OR bh.year = p_year)
  AND bh.is_active = TRUE
  ORDER BY bh.holiday_date ASC;
END; $$;

-- RPC to add bank holiday (admin only)
CREATE OR REPLACE FUNCTION public.rpc_add_bank_holiday(p_token UUID, p_year INTEGER, p_date DATE, p_name TEXT)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_user_id UUID; v_is_admin BOOLEAN; v_new_id UUID;
BEGIN
  SELECT user_id INTO v_user_id FROM public.sessions WHERE token = p_token AND expires_at > NOW() AND revoked_at IS NULL;
  IF v_user_id IS NULL THEN RETURN json_build_object('success', false, 'error', 'Invalid or expired session'); END IF;
  
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_user_id;
  IF NOT COALESCE(v_is_admin, FALSE) THEN RETURN json_build_object('success', false, 'error', 'Admin only'); END IF;
  
  IF p_year < 2000 OR p_year > 2100 THEN RETURN json_build_object('success', false, 'error', 'Invalid year'); END IF;
  IF p_date IS NULL THEN RETURN json_build_object('success', false, 'error', 'Invalid date'); END IF;
  IF EXTRACT(YEAR FROM p_date)::INTEGER != p_year THEN RETURN json_build_object('success', false, 'error', 'Date year must match the specified year'); END IF;
  IF p_name IS NULL OR p_name = '' THEN RETURN json_build_object('success', false, 'error', 'Holiday name required'); END IF;
  
  INSERT INTO public.bank_holidays (year, holiday_date, name, created_by)
  VALUES (p_year, p_date, p_name, v_user_id)
  RETURNING id INTO v_new_id;
  
  INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, new_values)
  VALUES (v_user_id, 'create', 'bank_holiday', v_new_id, json_build_object('year', p_year, 'date', p_date, 'name', p_name));
  
  RETURN json_build_object('success', true, 'id', v_new_id, 'message', 'Bank holiday added');
END; $$;

-- RPC to delete bank holiday (admin only)
CREATE OR REPLACE FUNCTION public.rpc_delete_bank_holiday(p_token UUID, p_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_user_id UUID; v_is_admin BOOLEAN; v_prev RECORD;
BEGIN
  SELECT user_id INTO v_user_id FROM public.sessions WHERE token = p_token AND expires_at > NOW() AND revoked_at IS NULL;
  IF v_user_id IS NULL THEN RETURN json_build_object('success', false, 'error', 'Invalid or expired session'); END IF;
  
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_user_id;
  IF NOT COALESCE(v_is_admin, FALSE) THEN RETURN json_build_object('success', false, 'error', 'Admin only'); END IF;
  
  SELECT * INTO v_prev FROM public.bank_holidays WHERE id = p_id;
  IF v_prev IS NULL THEN RETURN json_build_object('success', false, 'error', 'Bank holiday not found'); END IF;
  
  UPDATE public.bank_holidays SET is_active = FALSE WHERE id = p_id;
  
  INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, old_values)
  VALUES (v_user_id, 'delete', 'bank_holiday', p_id, to_jsonb(v_prev));
  
  RETURN json_build_object('success', true, 'message', 'Bank holiday removed');
END; $$;

-- RPC to get all bank holidays for multiple years (for frontend caching)
CREATE OR REPLACE FUNCTION public.rpc_get_all_bank_holidays(p_start_year INTEGER DEFAULT 2026, p_end_year INTEGER DEFAULT 2030)
RETURNS TABLE (id UUID, year INTEGER, holiday_date DATE, name TEXT)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT bh.id, bh.year, bh.holiday_date, bh.name
  FROM public.bank_holidays bh
  WHERE bh.year >= p_start_year
  AND bh.year <= p_end_year
  AND bh.is_active = TRUE
  ORDER BY bh.holiday_date ASC;
END; $$;

COMMIT;

-- Add user capability flags and preference sliders (additive, no behaviour change)
-- - Charge coverage flags: can_be_in_charge_day/night
-- - Safety rule flags: cannot_be_second_rn_day/night
-- - Night eligibility: can_work_nights
-- - Preferences: pref_shift_clustering, pref_night_appetite, pref_weekend_appetite, pref_leave_adjacency
-- Defaults chosen to preserve current behaviour (can_work_nights=true, other flags false, prefs=3/5).

BEGIN;

-- Capability flags (booleans)
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS can_be_in_charge_day boolean NOT NULL DEFAULT false;
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS can_be_in_charge_night boolean NOT NULL DEFAULT false;
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS cannot_be_second_rn_day boolean NOT NULL DEFAULT false;
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS cannot_be_second_rn_night boolean NOT NULL DEFAULT false;
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS can_work_nights boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.users.can_be_in_charge_day IS 'Charge-capable for day shifts';
COMMENT ON COLUMN public.users.can_be_in_charge_night IS 'Charge-capable for night shifts';
COMMENT ON COLUMN public.users.cannot_be_second_rn_day IS 'If true, cannot be one of only two RNs on day shifts';
COMMENT ON COLUMN public.users.cannot_be_second_rn_night IS 'If true, cannot be one of only two RNs on night shifts';
COMMENT ON COLUMN public.users.can_work_nights IS 'If false, user must not be assigned to night shifts';

-- Preference sliders (1-5, default 3)
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS pref_shift_clustering integer NOT NULL DEFAULT 3;
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS pref_night_appetite integer NOT NULL DEFAULT 3;
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS pref_weekend_appetite integer NOT NULL DEFAULT 3;
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS pref_leave_adjacency integer NOT NULL DEFAULT 3;

-- Ensure bounds 1-5 for preferences (add constraints only if missing)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'users_pref_shift_clustering_range'
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_pref_shift_clustering_range CHECK (pref_shift_clustering BETWEEN 1 AND 5);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'users_pref_night_appetite_range'
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_pref_night_appetite_range CHECK (pref_night_appetite BETWEEN 1 AND 5);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'users_pref_weekend_appetite_range'
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_pref_weekend_appetite_range CHECK (pref_weekend_appetite BETWEEN 1 AND 5);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'users_pref_leave_adjacency_range'
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_pref_leave_adjacency_range CHECK (pref_leave_adjacency BETWEEN 1 AND 5);
  END IF;
END $$;

COMMENT ON COLUMN public.users.pref_shift_clustering IS '1-5 preference: cluster shifts vs spread';
COMMENT ON COLUMN public.users.pref_night_appetite IS '1-5 preference: appetite for night shifts';
COMMENT ON COLUMN public.users.pref_weekend_appetite IS '1-5 preference: appetite for weekends';
COMMENT ON COLUMN public.users.pref_leave_adjacency IS '1-5 preference: keep leave adjacent to off days';

COMMIT;

BEGIN;

DROP POLICY IF EXISTS "Allow authenticated users to read patterns" ON public.pattern_definitions;

CREATE POLICY "pattern_definitions_no_direct" ON public.pattern_definitions
FOR ALL
USING (false)
WITH CHECK (false);

COMMIT;

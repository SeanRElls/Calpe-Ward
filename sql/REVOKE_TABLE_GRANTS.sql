BEGIN;

DO $$
DECLARE
  r record;
BEGIN
  -- Revoke all direct table access from anon/authenticated in public schema
  FOR r IN
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = 'public'
  LOOP
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM anon, authenticated;', r.tablename);
  END LOOP;

  -- Revoke sequence usage as well
  FOR r IN
    SELECT sequencename
    FROM pg_sequences
    WHERE schemaname = 'public'
  LOOP
    EXECUTE format('REVOKE ALL ON SEQUENCE public.%I FROM anon, authenticated;', r.sequencename);
  END LOOP;
END $$;

COMMIT;

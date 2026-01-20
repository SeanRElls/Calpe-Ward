-- Fix period_id type mismatch
-- swap_requests.period_id and swap_executions.period_id should be UUID to match rota_periods.id

BEGIN;

-- Change swap_requests.period_id from integer to uuid
ALTER TABLE swap_requests 
  ALTER COLUMN period_id TYPE uuid USING NULL;

-- Change swap_executions.period_id from integer to uuid (if it exists)
ALTER TABLE swap_executions 
  ALTER COLUMN period_id TYPE uuid USING NULL;

COMMIT;
-- Temporarily disable the max 5 requests per week trigger for bulk import
ALTER TABLE public.requests DISABLE TRIGGER trg_max_5_requests;

-- Now paste your INSERT statements here (from the CSV import)
-- The trigger will be re-enabled below

-- Re-enable the trigger after import
ALTER TABLE public.requests ENABLE TRIGGER trg_max_5_requests;

-- Verify the import by checking row counts
SELECT COUNT(*) as total_requests,
       COUNT(DISTINCT user_id) as users_with_requests
FROM requests;

# Fix for get_pending_swap_requests_for_me Function

## Problem
The function `get_pending_swap_requests_for_me` is returning HTTP 400 errors when called from the frontend. This prevents the swap request notifications from loading in rota.html.

## Solution
Apply the updated SQL function from `sql/update_swap_functions.sql` to your Supabase database.

## Steps to Apply

### Option 1: Using Supabase Dashboard (Recommended)

1. Go to https://app.supabase.com and sign in
2. Select your project
3. Go to **SQL Editor** (left sidebar)
4. Click **New Query**
5. Copy the entire contents of `sql/update_swap_functions.sql`
6. Paste it into the query editor
7. Click **Run** 
8. You should see "Success" message

### Option 2: Using PostgreSQL Client (if available)

```bash
psql -h "tbclufdtyefexwwitfsz.supabase.co" -U "postgres" -d "postgres" -f "sql/update_swap_functions.sql"
```

When prompted, enter your Supabase database password.

## What Changed
- Converted function from `plpgsql` to `sql` language for better performance
- Used explicit table references (`public.swap_requests`, `public.users`)
- Used `left join` instead of `inner join` for better null handling
- Added `coalesce()` to handle missing user names
- Added proper type casting with `::`text

## Testing
After applying:

1. Hard refresh rota.html (Ctrl+Shift+R)
2. Check browser console (F12) for any errors
3. Look for notifications bell to load without 400 errors
4. Swap request notifications should now appear if there are any pending requests

## If Still Getting 400 Error

Check the Supabase function status:
1. Go to **SQL Editor**
2. Run: `SELECT * FROM information_schema.routines WHERE routine_name = 'get_pending_swap_requests_for_me';`
3. Verify the function exists and the signature is correct

If the function doesn't exist, re-run the SQL update script.

## Related Functions

Other swap-related RPC functions that are working:
- `admin_get_swap_requests` - for admin swap management
- `admin_get_swap_executions` - for admin swap history
- `staff_request_shift_swap` - to create a swap request
- `staff_respond_to_swap_request` - to accept/decline swaps

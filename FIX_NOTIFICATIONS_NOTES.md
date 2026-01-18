# Fixes Required for Notifications and Shift Grid

## Issues Fixed in Code

### 1. window.currentToken Not Set
**File**: `requests.html`
**Issue**: Notifications and other RPC calls were using `window.currentToken` which was never set
**Fix**: Added `window.currentToken = token;` in `initPage()` function

### 2. window.currentUser Not Available to shift-functions.js
**File**: `requests.html`  
**Issue**: `shift-functions.js` checks `window.currentUser` but `initPage()` only set local `currentUser` variable
**Fix**: Added `window.currentUser = userData;` in `initPage()` function

### 3. Notifications Function Missing from Database
**File**: SQL - needs to be deployed
**Issue**: `get_notices_for_user(p_token uuid)` RPC function was dropped during migration but never recreated
**Fix**: Created `sql/RECREATE_NOTICES_FUNCTION.sql` with proper function definition

## SQL to Deploy

**File**: `sql/RECREATE_NOTICES_FUNCTION.sql`

Run this in Supabase SQL Editor to recreate the missing function:

```sql
-- Recreate get_notices_for_user function with token-based authentication
DROP FUNCTION IF EXISTS public.get_notices_for_user(uuid);

CREATE OR REPLACE FUNCTION public.get_notices_for_user(p_token uuid)
RETURNS TABLE(
  id uuid,
  title text,
  body_en text,
  body_es text,
  version integer,
  is_active boolean,
  updated_at timestamp with time zone,
  created_by uuid,
  created_by_name text,
  target_all boolean,
  target_roles integer[],
  acknowledged_at timestamp with time zone,
  ack_version integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT
    n.id,
    n.title,
    n.body_en,
    n.body_es,
    n.version,
    n.is_active,
    n.updated_at,
    n.created_by,
    u.name as created_by_name,
    n.target_all,
    COALESCE(array_agg(nt.role_id) FILTER (WHERE nt.role_id IS NOT NULL), '{}'::integer[]) as target_roles,
    na.acknowledged_at,
    na.version as ack_version
  FROM notices n
  LEFT JOIN users u ON u.id = n.created_by
  LEFT JOIN notice_targets nt ON nt.notice_id = n.id
  LEFT JOIN notice_ack na ON na.notice_id = n.id
    AND na.user_id = (SELECT user_id FROM sessions WHERE token = p_token AND expires_at > now() AND revoked_at IS NULL)
  WHERE n.is_active = true
  GROUP BY n.id, u.id, na.user_id, na.acknowledged_at, na.version
  ORDER BY n.updated_at DESC;
$$;

-- Grant permissions
GRANT ALL ON FUNCTION public.get_notices_for_user(uuid) TO anon;
GRANT ALL ON FUNCTION public.get_notices_for_user(uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_notices_for_user(uuid) TO service_role;
```

## Next Steps

1. Copy and run the SQL from `sql/RECREATE_NOTICES_FUNCTION.sql` in your Supabase SQL Editor
2. Refresh the requests.html page
3. Notifications bell should now load and display notices
4. Shift grid should populate with user data

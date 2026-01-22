# Database & RPC Function Troubleshooting Guide
**Calpe Ward Post-Codex Security Migration**

---

## 🔍 Database Connection Verification

### Check Database Connection

```sql
-- Test basic connectivity
SELECT version();

-- Result should show: PostgreSQL 17.6
```

### Verify RLS Policies are Enabled

```sql
SELECT 
    tablename,
    (SELECT Count(*) FROM pg_policies WHERE schemaname='public' AND tablename=t.tablename) as policy_count
FROM pg_tables t
WHERE schemaname = 'public'
ORDER BY tablename;

-- Should show policy_count > 0 for all critical tables
```

---

## 🔐 RPC Function Signature Reference

### Critical Comment Functions

#### `rpc_get_rota_assignment_comments`
```sql
-- Signature
CREATE OR REPLACE FUNCTION rpc_get_rota_assignment_comments(
    p_token UUID, 
    p_assignment_ids BIGINT[]
)
RETURNS SETOF rota_assignment_comments;

-- Correct usage (JavaScript)
supabaseClient.rpc('rpc_get_rota_assignment_comments', {
    p_token: sessionStorage.getItem('calpe_ward_token'),
    p_assignment_ids: [12345]  // Array of assignment IDs
});

-- Common mistakes to avoid:
// ❌ Wrong: single value instead of array
p_assignment_ids: 12345

// ❌ Wrong: missing token
rpc('rpc_get_rota_assignment_comments', { p_assignment_ids: [12345] })

// ❌ Wrong: incorrect parameter name
rpc('rpc_get_rota_assignment_comments', { assignment_ids: [12345], token: '' })
```

#### `rpc_add_rota_assignment_comment`
```sql
-- Signature
CREATE OR REPLACE FUNCTION rpc_add_rota_assignment_comment(
    p_token UUID,
    p_assignment_id BIGINT,
    p_comment TEXT,
    p_comment_visibility TEXT DEFAULT 'all_staff'::text
)
RETURNS rota_assignment_comments;

-- Correct usage (JavaScript)
supabaseClient.rpc('rpc_add_rota_assignment_comment', {
    p_token: sessionStorage.getItem('calpe_ward_token'),
    p_assignment_id: 12345,
    p_comment: 'Comment text here',
    p_comment_visibility: 'all_staff'  // or 'admin_only'
});

-- Common mistakes to avoid:
// ❌ Wrong: p_comment_text instead of p_comment
p_comment_text: 'text'

// ❌ Wrong: missing token
rpc('rpc_add_rota_assignment_comment', { p_assignment_id: 12345, ... })

// ❌ Wrong: using assignment object instead of ID
p_assignment_id: assignmentObject  // should be just the ID number
```

#### `rpc_delete_rota_assignment_comment`
```sql
-- Signature
CREATE OR REPLACE FUNCTION rpc_delete_rota_assignment_comment(
    p_token UUID,
    p_comment_id BIGINT
)
RETURNS void;

-- Correct usage (JavaScript)
supabaseClient.rpc('rpc_delete_rota_assignment_comment', {
    p_token: sessionStorage.getItem('calpe_ward_token'),
    p_comment_id: 54321  // Comment ID to delete
});

-- Common mistakes to avoid:
// ❌ Wrong: comment object instead of ID
p_comment_id: commentObject

// ❌ Wrong: assignment ID instead of comment ID
p_comment_id: assignmentId  // should be comment ID
```

#### `upsert_week_comment` ⚠️ DATABASE ISSUE
```sql
-- Signature
CREATE OR REPLACE FUNCTION upsert_week_comment(
    p_token UUID,
    p_week_id UUID,
    p_comment TEXT
)
RETURNS TABLE(user_id UUID, week_id UUID, comment TEXT);

-- Correct usage (JavaScript)
supabaseClient.rpc('upsert_week_comment', {
    p_token: sessionStorage.getItem('calpe_ward_token'),
    p_week_id: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',  // UUID
    p_comment: 'Week comment text'
});

-- ⚠️ KNOWN ISSUE:
// This function has a database-level column ambiguity error
// RPC parameter order has been corrected but DB function needs review
// Error message: "ambiguous column reference week_id"
// 
// If you get this error:
// 1. The RPC parameters are correct
// 2. The PostgreSQL function definition needs to use schema-qualified column names
// 3. Contact database administrator to review function definition

-- To check the function definition:
SELECT pg_get_functiondef('public.upsert_week_comment(uuid, uuid, text)'::regprocedure);

-- Common mistakes to avoid:
// ❌ Wrong: string UUID instead of UUID type
p_week_id: 'abc123'  // Should be proper UUID format

// ❌ Wrong: parameter order
{ p_week_id, p_comment, p_token }  // should be (token, week_id, comment)
```

---

## 🔧 Debugging RPC Calls

### Enable Detailed Logging

```javascript
// Add to rota.html or requests.html for debugging
const originalRpc = supabaseClient.rpc;
supabaseClient.rpc = async function(functionName, params) {
    console.log(`[RPC CALL] ${functionName}`, params);
    try {
        const result = await originalRpc.call(this, functionName, params);
        console.log(`[RPC SUCCESS] ${functionName}`, result);
        return result;
    } catch (error) {
        console.error(`[RPC ERROR] ${functionName}`, error);
        throw error;
    }
};
```

### Common RPC Error Codes

| Error | Meaning | Solution |
|-------|---------|----------|
| `400 Bad Request` | Invalid parameters | Check parameter names and types match signature |
| `401 Unauthorized` | Invalid token or permissions | Verify token in sessionStorage, check RLS policies |
| `402 Payment Required` (Supabase) | Rate limit exceeded | Wait and retry, check for infinite loops |
| `403 Forbidden` | Permission denied | Verify user role and permissions |
| `404 Not Found` | RPC function doesn't exist | Verify function name spelling |
| `500 Internal Server Error` | Database function error | Check database logs, review function definition |

---

## 🔍 RLS Policy Verification

### Check RLS is Blocking Direct Access

```javascript
// This should FAIL with "new row violates row-level security policy"
const { data, error } = await supabaseClient
    .from('rota_assignments')
    .select()
    .limit(1);

console.log(error);  
// Should show RLS denial, NOT data

// Correct way is through RPC:
const { data, error } = await supabaseClient.rpc('rpc_get_rota_assignments', {
    p_token: sessionStorage.getItem('calpe_ward_token'),
    p_period_id: periodId,
    p_include_draft: true
});

console.log(data);  // Should have data
```

### Verify SECURITY DEFINER Functions

```sql
-- Check function security context
SELECT 
    proname,
    prosecdef  -- true if SECURITY DEFINER, false if SECURITY INVOKER
FROM pg_proc
WHERE proname IN (
    'rpc_get_rota_assignment_comments',
    'rpc_add_rota_assignment_comment',
    'rpc_delete_rota_assignment_comment',
    'upsert_week_comment'
)
ORDER BY proname;

-- All should show prosecdef = true
```

---

## 🔑 Token Management & Debugging

### Check Active Token

```javascript
// In browser console
const token = sessionStorage.getItem('calpe_ward_token');
console.log('Current token:', token);

// Verify it's a valid UUID
const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
console.log('Valid UUID:', uuidRegex.test(token));

// Check session table in database
SELECT 
    user_id,
    token,
    created_at,
    expires_at,
    is_active
FROM sessions
WHERE token = 'YOUR_TOKEN_HERE';
```

### Handle Token Expiration

```javascript
// Check if token is expired
async function isTokenExpired(token) {
    const { data, error } = await supabaseClient.rpc('validate_session', {
        p_token: token
    });
    
    if (error) {
        console.log('Token expired or invalid:', error);
        return true;
    }
    
    return false;
}

// Refresh UI if token invalid
if (await isTokenExpired(currentToken)) {
    redirectToLogin('Session expired. Please log in again.');
}
```

---

## 🛠️ Troubleshooting Specific Issues

### Issue: "Comments not loading on published shift"

**Diagnosis:**
```javascript
// Check browser console for RPC error
// Should see call to: rpc_get_rota_assignment_comments

// Verify call parameters
console.log({
    p_token: sessionStorage.getItem('calpe_ward_token'),
    p_assignment_ids: [assignmentId]  // Should be array with single ID
});
```

**Solution:**
1. Verify `window.lastPublishedCell` is set correctly
2. Check assignment ID is being passed as array: `[id]` not `id`
3. Verify token exists in sessionStorage
4. Check browser console for specific error message

**Database Check:**
```sql
-- Verify comment exists for this assignment
SELECT * FROM rota_assignment_comments 
WHERE rota_assignment_id = YOUR_ASSIGNMENT_ID
ORDER BY created_at DESC;
```

---

### Issue: "Shift picker modal shows 'No shifts available'"

**Diagnosis:**
```javascript
// In browser console, check if shifts variable is populated
console.log('Global shifts variable:', window.shifts || shifts);

// Should show array of shift objects:
// [
//   { id: 1, code: 'EARLY', label: 'Early', hours_value: 8, ... },
//   { id: 2, code: 'LATE', label: 'Late', hours_value: 8, ... }
// ]

// If undefined or empty, check if getDraftShifts callback is working
console.log('getDraftShifts callback result:', getDraftShifts?.());
```

**Solution:**
1. Verify global `shifts` variable is declared at line ~638 of rota.html
2. Check that assignment to `shifts` happens: `shifts = shiftsData || [];`
3. Verify `getDraftShifts` callback returns the global shifts: `return shifts;`
4. Check shift_editor.js is loaded correctly

**Database Check:**
```sql
-- Verify shifts exist in database
SELECT id, code, label FROM shifts 
WHERE active = true 
ORDER BY code;

-- If empty, add shifts:
INSERT INTO shifts (code, label, hours_value, day_or_night, active)
VALUES ('EARLY', 'Early Shift', 8, 'day', true);
```

---

### Issue: "Week comments save fails with ambiguous column error"

**Diagnosis:**
```javascript
// Error message in browser console:
// "ambiguous column reference week_id"

// This is a DATABASE FUNCTION issue, not an RPC issue
// The RPC parameters are correct, but the PostgreSQL function
// has a column reference ambiguity in its definition
```

**Solution - Short Term:**
1. RPC parameters have been corrected in requests.html
2. If still failing, wait for database function fix

**Solution - Long Term:**
1. Check function definition:
   ```sql
   SELECT pg_get_functiondef('public.upsert_week_comment(uuid, uuid, text)'::regprocedure);
   ```

2. Look for unqualified column names like `week_id` that should be `week_comments.week_id`

3. Function likely needs to be rewritten with schema qualification:
   ```sql
   CREATE OR REPLACE FUNCTION upsert_week_comment(...)
   AS $$
   DECLARE
   BEGIN
       -- Use fully qualified names:
       INSERT INTO week_comments(user_id, week_id, comment, ...)
       -- not just: INSERT INTO week_comments(user_id, week_id, ...)
   ```

---

### Issue: "Admin features not working - permission denied"

**Diagnosis:**
```javascript
// Check user permissions
const { data: perms, error } = await supabaseClient.rpc('rpc_get_user_permissions', {
    p_token: sessionStorage.getItem('calpe_ward_token')
});

console.log('User permissions:', perms);

// Should include admin-level permissions like:
// 'admin_manage_users', 'admin_manage_periods', 'admin_publish'
```

**Solution:**
1. Verify user has admin role in database
2. Check user permissions are assigned
3. Verify permission_groups and user_permission_groups tables have mappings

**Database Check:**
```sql
-- Check user role
SELECT id, name, role_id FROM users WHERE id = 'user_uuid';

-- Check permissions
SELECT p.key, p.description 
FROM permissions p
JOIN user_permission_groups upg ON upg.permission_group_id = p.group_id
WHERE upg.user_id = 'user_uuid';

-- Add admin permissions if needed
INSERT INTO user_permission_groups(user_id, permission_group_id)
SELECT 'user_uuid', id FROM permission_groups WHERE name = 'admin';
```

---

## 📊 Database Query Reference

### Verify All Tables Exist

```sql
SELECT tablename FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY tablename;
```

### Check RPC Function Count

```sql
SELECT COUNT(*) FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname LIKE 'rpc_%';

-- Should return: 37
```

### Verify All Users Can Access RPCs

```sql
-- Check grants on critical RPC
SELECT grantee, privilege_type FROM aclexplode(proacl)
WHERE proname = 'rpc_get_rota_assignment_comments'
LIMIT 10;
```

### Check Active Sessions

```sql
SELECT user_id, token, created_at, expires_at, is_active
FROM sessions
WHERE is_active = true
ORDER BY created_at DESC
LIMIT 10;
```

---

## 🚀 Performance Optimization Tips

### Check Query Performance

```sql
-- Enable query logging
SET log_min_duration_statement = 1000;  -- Log queries > 1 second

-- Then check logs for slow queries
-- SELECT * FROM pg_stat_statements ORDER BY mean_exec_time DESC;
```

### Optimize Common Queries

```sql
-- Index for fast assignment lookup
CREATE INDEX IF NOT EXISTS idx_rota_assignments_period_date 
ON rota_assignments(rota_period_id, assignment_date);

-- Index for fast comment lookup
CREATE INDEX IF NOT EXISTS idx_rota_comments_assignment 
ON rota_assignment_comments(rota_assignment_id);

-- Index for fast requests lookup
CREATE INDEX IF NOT EXISTS idx_requests_user_date 
ON requests(user_id, request_date);
```

---

## 📞 Support & Escalation

### If RPC Function Returns Error

1. **Check error message**: Copy full error from browser console
2. **Verify parameters**: Compare call against function signature (above)
3. **Check token**: Ensure token is valid and in sessionStorage
4. **Check database**: Run SQL queries to verify data exists
5. **Check logs**: Review PostgreSQL logs for function execution errors

### If Database Query Fails

1. **Check connection**: Run `SELECT version();` to verify connectivity
2. **Check permissions**: Verify role can access tables via RLS
3. **Check RLS policies**: Ensure policies aren't blocking valid access
4. **Check audit logs**: Look for permission denial entries

### If Application Crashes

1. **Check browser console**: Look for JavaScript errors (not RPC errors)
2. **Check network tab**: Look for failed HTTP requests
3. **Refresh page**: Clear cache and reload
4. **Check sessionStorage**: Verify token is present
5. **Re-login**: Clear session and log in again

---

## 📝 Logging & Debugging Checklist

- [ ] RPC calls logged with parameters
- [ ] RPC responses logged with results
- [ ] Error messages include error code and description
- [ ] Token validation logged on page load
- [ ] Permission checks logged before sensitive operations
- [ ] Database state verified before and after critical operations
- [ ] Browser console clear of warnings/errors

---

**Remember: All database operations must go through RPC functions. Direct `.from()` queries are blocked by RLS policies.**

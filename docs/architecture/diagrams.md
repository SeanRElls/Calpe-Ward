# Token-Only RPC Architecture Diagram & Flow Charts

---

## 1. Authentication Flow (High Level)

```
┌─────────────────────────────────────────────────────────────────┐
│                        USER LOGS IN                              │
└─────────────────────────────────────────────────────────────────┘
                              ↓
        ┌─────────────────────────────────────┐
        │   Frontend: verify_pin_login(PIN)   │
        └─────────────────────────────────────┘
                              ↓
        ┌─────────────────────────────────────────────────┐
        │   Backend RPC: verify_pin_login(p_pin)          │
        │   - Find user by PIN                            │
        │   - Create session record (with token)          │
        │   - Return token (UUID)                         │
        └─────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────┐
│ Frontend stores:                                        │
│   - window.currentToken = 'abc123...' (UUID)           │
│   - window.currentUser = { id, name, role_id, ... }    │
│   - sessionStorage['PIN_' + userId] = '1234' (local)   │
└─────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────┐
│              USER MAKES RPC CALL                        │
│   Example: Get unread notices                          │
└─────────────────────────────────────────────────────────┘
                              ↓
        ┌─────────────────────────────────────┐
        │   Frontend calls:                   │
        │   rpc('get_unread_notices', {       │
        │     p_token: window.currentToken    │
        │   })                                │
        │   ❌ Does NOT send p_user_id        │
        │   ❌ Does NOT send p_pin            │
        └─────────────────────────────────────┘
                              ↓
        ┌─────────────────────────────────────────────────┐
        │   Backend RPC: get_unread_notices(p_token)      │
        │   1. Call require_session_permissions()         │
        │      - Look up token in sessions table          │
        │      - Verify not expired/revoked               │
        │      - Return user_id (UUID)                    │
        │   2. Use returned user_id to fetch notices      │
        │   3. Return notices to frontend                 │
        └─────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────┐
│   Frontend receives unread notices                      │
│   (None sent to backend; all inferred from token)      │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Permission Gate Flow (Admin Operations)

```
┌──────────────────────────────────────────────────────┐
│   Admin user tries: admin_approve_swap_request()     │
│   Frontend: rpc('admin_approve_swap_request', {      │
│     p_token: window.currentToken,                    │
│     p_swap_request_id: '...'                         │
│   })                                                 │
└──────────────────────────────────────────────────────┘
                           ↓
        ┌────────────────────────────────────────┐
        │ Backend RPC starts                      │
        │ Step 1: Validate token                 │
        │         v_uid := require_session_      │
        │                  permissions(token)    │
        └────────────────────────────────────────┘
                           ↓
                    ┌──────────────┐
                    │ Token valid? │
                    └──────────────┘
                     /            \
                  YES              NO
                   ↓                ↓
        ┌────────────────────┐   RAISE
        │ Get user.is_admin  │   'invalid_session'
        └────────────────────┘   ❌
                   ↓
            ┌──────────────┐
            │ is_admin=?   │
            └──────────────┘
             /             \
           YES              NO
            ↓                ↓
      ✅ ALLOW        Check Permission
       (bypass)             ↓
                    ┌──────────────────────┐
                    │ User has permission? │
                    │ 'manage_shifts'      │
                    └──────────────────────┘
                      /              \
                    YES              NO
                     ↓                ↓
                  ✅ ALLOW        RAISE
                              'permission_denied'
                                 ❌
                     ↓
        ┌────────────────────────────────┐
        │ Execute swap approval logic     │
        │ - Update swap_requests         │
        │ - Create swap_executions       │
        │ - Return success               │
        └────────────────────────────────┘
```

---

## 3. Function Call Patterns

### Staff Function Pattern (Token-Only)

```sql
CREATE OR REPLACE FUNCTION public.set_request_cell(
  p_token uuid,              -- ONLY authentication parameter
  p_date date,               -- Business parameters start here
  p_value text,
  p_important_rank smallint
)
RETURNS TABLE(success boolean, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;  -- Inferred from token, never from client
BEGIN
  -- Step 1: Validate token and get user_id
  v_uid := public.require_session_permissions(p_token, null);
  
  -- Step 2: Use v_uid for all authorization
  -- (User cannot impersonate anyone else because v_uid comes from token)
  UPDATE public.assignment_comments
  SET value = p_value,
      important_rank = p_important_rank
  WHERE user_id = v_uid AND date = p_date;
  
  -- Step 3: Return result
  RETURN QUERY SELECT true, 'success'::text;
END;
$$;
```

**Key Points**:
- ❌ No `p_user_id` parameter (prevents impersonation)
- ❌ No `p_pin` parameter (PIN never sent over network)
- ✅ Only `p_token` for identity
- ✅ User_id inferred from token inside function
- ✅ SECURITY DEFINER + SET search_path

---

### Admin Function Pattern (Token-Only + is_admin Bypass)

```sql
CREATE OR REPLACE FUNCTION public.admin_approve_swap_request(
  p_token uuid,              -- ONLY authentication parameter
  p_swap_request_id uuid     -- Business parameters
)
RETURNS TABLE(success boolean, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
BEGIN
  -- Step 1: Validate token and get admin user_id
  v_admin_uid := public.require_session_permissions(p_token, null);
  -- ⚠️ Token ALWAYS validated, even for admins
  
  -- Step 2: Check if user is admin
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  
  -- Step 3: Permission gate (unless admin)
  IF NOT v_is_admin THEN
    -- Non-admin must have explicit permission
    PERFORM public.require_session_permissions(p_token, ARRAY['manage_shifts']);
    -- If permission missing, this raises 'permission_denied'
  END IF;
  -- If is_admin=true, we skip the permission check entirely
  
  -- Step 4: Execute approved swap logic
  UPDATE public.swap_requests SET status = 'approved' WHERE id = p_swap_request_id;
  INSERT INTO public.swap_executions (...) VALUES (...);
  
  RETURN QUERY SELECT true, 'Swap approved'::text;
END;
$$;
```

**Key Points**:
- ✅ Token ALWAYS validated first (defense in depth)
- ✅ is_admin check skips permission gate (bypass)
- ✅ Non-admin still requires valid token + permission
- ✅ Both paths properly gated (no implicit access)

---

## 4. System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                       FRONTEND (Browser)                         │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │  app.js / admin.js / swap-functions.js                    │   │
│  │                                                            │   │
│  │  RPC Call:                                                │   │
│  │  supabaseClient.rpc('get_unread_notices', {              │   │
│  │    p_token: window.currentToken  ← Token from login      │   │
│  │  })                                                        │   │
│  └───────────────────────────────────────────────────────────┘   │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │  window object:                                            │   │
│  │  - currentToken = 'a1b2c3...' (UUID from login)           │   │
│  │  - currentUser = { id, name, role_id, is_admin, ... }     │   │
│  │  - sessionStorage['PIN_<id>'] = '1234' (LOCAL ONLY)       │   │
│  └───────────────────────────────────────────────────────────┘   │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │  ❌ Does NOT send:                                         │   │
│  │     - p_user_id                                           │   │
│  │     - p_admin_id                                          │   │
│  │     - p_pin                                               │   │
│  │     - Any user identifying info                           │   │
│  └───────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
                              ↓
                        HTTPS Network
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│                  SUPABASE POSTGRES (Backend)                      │
│                                                                   │
│  ┌────────────────────────────────────────────────────────┐      │
│  │  RPC Handler: get_unread_notices(p_token)             │      │
│  │                                                         │      │
│  │  SECURITY DEFINER, SET search_path                    │      │
│  │                                                         │      │
│  │  1. v_uid := require_session_permissions(p_token)     │      │
│  │     (Validates token, returns user_id)                │      │
│  │                                                         │      │
│  │  2. SELECT * FROM notices WHERE .... AND user_id=v_uid│      │
│  │     (Uses token-derived user_id, not client-supplied) │      │
│  └────────────────────────────────────────────────────────┘      │
│                                                                   │
│  ┌────────────────────────────────────────────────────────┐      │
│  │  Supporting Tables:                                    │      │
│  │                                                         │      │
│  │  sessions (token, user_id, expires_at, revoked_at)   │      │
│  │  users (id, name, role_id, is_admin, ...)            │      │
│  │  user_permission_assignments (user_id, group_id)     │      │
│  │  permission_group_permissions (group_id, perm_key)   │      │
│  │  notices (id, title, body_en, body_es, ...)          │      │
│  │  assignment_comments (user_id, date, value, ...)     │      │
│  │  swap_requests (id, initiator_id, status, ...)       │      │
│  │  swap_executions (id, initiator_id, counterparty_id) │      │
│  └────────────────────────────────────────────────────────┘      │
│                                                                   │
│  ┌────────────────────────────────────────────────────────┐      │
│  │  require_session_permissions(token, permissions):     │      │
│  │                                                         │      │
│  │  1. Look up token in sessions table                   │      │
│  │  2. Check if expired/revoked                          │      │
│  │  3. If permissions array provided:                    │      │
│  │     - Check if user.is_admin = true (bypass)          │      │
│  │     - If not admin, check permission keys             │      │
│  │  4. Return user_id or raise exception                 │      │
│  └────────────────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────────────────┘
```

---

## 5. Data Flow: Swap Request Example

```
Staff User 1                    Admin                   Staff User 2
    │                            │                           │
    │  1. Request swap           │                           │
    │  p_token: "token1"         │                           │
    ├───────────────────────────→ [RPC] ──────────────────→  │
    │  staff_request_             │                           │
    │  shift_swap()              │                           │
    │                            │                           │
    │                            │  Create swap_request      │
    │                            │  - status: 'pending'      │
    │                            │  - initiator_id: u1       │
    │                            │                           │
    ├─────────────────────────────────────────────────────→  │
    │                            │                    Notify  │
    │                            │                           │
    │                            │  2. Counterparty accepts  │
    │                            │  p_token: "token2"        │
    │                            │ ←──────────────────────── │
    │                            │   staff_respond_to_       │
    │                            │   swap_request()          │
    │                            │                           │
    │                            │  Update swap_request      │
    │                            │  - status: 'accepted'     │
    │                            │ ───────────────────────→  │
    │                            │  Notify counterparty      │
    │                            │                      ┌────┤
    │                            │                      │    │
    │  3. Admin approves         │                      │    │
    │ ←────────────────────────  │                      │    │
    │                            │   admin_approve_    │    │
    │  Notify both              │   swap_request()    │    │
    │ ───────────────────────→  │  p_token: "admin_token"   │
    │                            │                      │    │
    │                            │  Verify token       │    │
    │                            │  Verify admin OR    │    │
    │                            │    manage_shifts    │    │
    │                            │                      │    │
    │                            │  Execute swap:      │    │
    │                            │  - Swap shifts in   │    │
    │                            │    rota_assignments │    │
    │                            │  - Create swap_     │    │
    │                            │    executions entry │    │
    │                            │                      │    │
    │  Shifts swapped ←─────────────────────────────── │    │
    │                            │  ←──────────────────────│
    │                            │                      Shifts
    │                            │                      swapped
```

---

## 6. Permission Check Logic (Detailed)

```
require_session_permissions(token, ['manage_shifts'])
                                │
                                ↓
                    ┌─────────────────────┐
                    │ SELECT FROM sessions │
                    │ WHERE token = ?      │
                    └─────────────────────┘
                     /              \
              Found                Not Found
               ↓                      ↓
        ┌──────────────────┐    RAISE 'invalid_session'
        │ Check expiry     │        ❌
        │ & revocation     │
        └──────────────────┘
         /                 \
    Valid              Invalid
     ↓                   ↓
  Continue         RAISE 'invalid_session'
     ↓                  ❌
┌──────────────────────────────┐
│ Permissions required?        │
│ (Is array non-empty?)        │
└──────────────────────────────┘
 /                              \
No                              Yes
↓                                ↓
✅ RETURN user_id      ┌────────────────────┐
                       │ SELECT is_admin     │
                       │ FROM users          │
                       │ WHERE id = user_id  │
                       └────────────────────┘
                        /                  \
                       YES                 NO
                        ↓                   ↓
                  ✅ RETURN         ┌──────────────────────┐
                   user_id           │ SELECT permission_key│
                   (Admin            │ FROM user_            │
                    bypass)          │ permission_assignments│
                                     └──────────────────────┘
                                             ↓
                                    ┌────────────────────┐
                                    │ User has ALL       │
                                    │ required perms?    │
                                    └────────────────────┘
                                    /                  \
                                  YES                 NO
                                   ↓                   ↓
                            ✅ RETURN      RAISE 'permission_denied'
                             user_id             ❌
```

---

## 7. Security Layers (Defense in Depth)

```
┌─────────────────────────────────────────────────────────┐
│  LAYER 1: RPC Signature Enforcement                     │
│  - Only accepts p_token (UUID)                          │
│  - Rejects attempts to pass p_user_id, p_pin, etc.      │
│  - Frontend must be updated to match                    │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│  LAYER 2: Session Token Validation                      │
│  - Look up token in sessions table                      │
│  - Verify not expired (expires_at > NOW())              │
│  - Verify not revoked (revoked_at IS NULL)              │
│  - Return user_id if valid, else raise 'invalid_session'│
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│  LAYER 3: Permission Gate (Unless is_admin)             │
│  - Check user.is_admin = true (admin bypass)            │
│  - If not admin, verify required permission keys        │
│  - Permissions stored in user_permission_assignments    │
│  - If permission missing, raise 'permission_denied'     │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│  LAYER 4: SECURITY DEFINER + search_path                │
│  - RPC executes as function owner (postgres)            │
│  - NOT as caller (frontend)                             │
│  - Prevents caller from accessing sensitive tables      │
│  - search_path = ('public', 'pg_temp') prevents         │
│    malicious function/table lookup                      │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│  LAYER 5: RLS (Row Level Security) on Tables            │
│  - Tables have RLS policies enabled                     │
│  - Direct table access requires auth                    │
│  - RPCs enforce auth at function level anyway           │
│  - RPCs + RLS = defense in depth                        │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│  LAYER 6: User_id Inference (No Client Supply)          │
│  - Backend NEVER trusts p_user_id from client           │
│  - user_id always derived from token (v_uid)            │
│  - Prevents user impersonation attacks                  │
└─────────────────────────────────────────────────────────┘
```

---

## 8. Error Handling Decision Tree

```
                    RPC Call Made
                         │
                         ↓
                ┌────────────────────┐
                │ Is token valid?     │
                └────────────────────┘
                /                    \
              NO                    YES
               ↓                     ↓
        ❌ 'invalid_session'   ┌──────────────────┐
                               │ Permission check? │
                               └──────────────────┘
                               /                  \
                             NO                  YES
                              ↓                   ↓
                        ✅ Proceed        ┌─────────────────┐
                                          │ User is admin?  │
                                          └─────────────────┘
                                          /                 \
                                        YES                NO
                                         ↓                  ↓
                                   ✅ Proceed      ┌──────────────────┐
                                                  │ Has permission?   │
                                                  └──────────────────┘
                                                  /                  \
                                                YES                 NO
                                                 ↓                   ↓
                                           ✅ Proceed      ❌ 'permission_denied'

Possible Errors:
- 'invalid_session' → Token not found/expired/revoked
- 'permission_denied' → User lacks required permission (non-admin)
- Business errors → Swap not found, period not found, etc.
```

---

## 9. Deployment Sequence Diagram

```
Timeline:  |─────────────────────────────────────────────────────────|
           T-0  T+5min  T+10min T+15min T+20min  T+1hr   T+24hr

Database:  ☐────⚙️────────✅───────────────────────────✅────────✅
           Pre   SQL    Post-   Continue             Verify
           Check Migrate Migration               24h OK

Frontend:  ☐─────────────⚙️───────✅────────────────✅────────✅
           Pre    (waiting)   Deploy    Verify  Continue
           Check              .js/.html  OK      24h OK

Users:     ☐─────────────────────────────⚠️────────✅────────✅
           Unaffected          ↑ Need   Working  All clear
           until here         re-login  (might
                              see brief
                              errors)

Monitoring:☐─────────────────────────────────────📊────────✅
           Off              On (Smoke Testing)   Stats OK
                                       ↑
                                 Close watch
                                 first 24h


Tasks:
✅ = Completed successfully
⚙️ = In progress
☐ = Not started
⚠️ = User action required
📊 = Monitoring active
```

---

## 10. Before/After Comparison

### BEFORE (PIN-Based)
```javascript
// Frontend
const { data, error } = await supabaseClient.rpc(
  'get_unread_notices',
  {
    p_user_id: window.currentUser.id,    // ❌ Client supplies identity
    p_token: window.currentToken,        // ⚠️ Token ignored/underutilized
    p_pin: sessionStorage.getItem(...)  // ❌ PIN sent over network (!!)
  }
);
```

```sql
-- Backend
CREATE OR REPLACE FUNCTION get_unread_notices(
  p_user_id uuid,        -- ❌ Trusts client-supplied ID
  p_token uuid,          -- ⚠️ Checked but overridden by p_user_id
  p_pin text
) AS $$
BEGIN
  -- Logic uses p_user_id, ignoring v_uid from token
  -- ❌ User could impersonate others by changing p_user_id
  RETURN QUERY SELECT * FROM notices WHERE user_id = p_user_id;
END;
$$;
```

**Problems**:
- ❌ PIN sent over network (shouldn't happen)
- ❌ User can impersonate others (change p_user_id)
- ❌ Token validation underutilized
- ❌ Multiple parameters for same user (confusing, error-prone)

---

### AFTER (Token-Only)
```javascript
// Frontend
const { data, error } = await supabaseClient.rpc(
  'get_unread_notices',
  {
    p_token: window.currentToken  // ✅ Token is sole identifier
  }
  // ✅ p_user_id NOT sent
  // ✅ p_pin NOT sent
);
```

```sql
-- Backend
CREATE OR REPLACE FUNCTION get_unread_notices(
  p_token uuid  -- ✅ ONLY parameter for identity
) RETURNS TABLE(...) AS $$
DECLARE
  v_uid uuid;  -- ✅ Derived from token, never from client
BEGIN
  v_uid := require_session_permissions(p_token, null);
  -- ✅ User cannot impersonate (v_uid is from token)
  -- ✅ All business logic uses v_uid
  RETURN QUERY SELECT * FROM notices WHERE user_id = v_uid;
END;
$$;
```

**Improvements**:
- ✅ PIN never sent over network
- ✅ User cannot impersonate (identity from token only)
- ✅ Single clear identity source (token)
- ✅ Consistent pattern across all RPCs
- ✅ Better security baseline

---

## Summary

The migration creates a **secure, token-only authentication layer** where:

1. **Frontend** sends only token + business parameters
2. **Backend** validates token, derives user identity, enforces permissions
3. **Admin bypass** works via `is_admin` flag while still requiring valid token
4. **Defense in depth** with multiple security layers (token validation, permissions, SECURITY DEFINER, RLS)
5. **Consistent patterns** across all staff and admin functions

This prevents:
- User impersonation (user_id from token only)
- PIN exposure (never sent to server)
- Permission bypass (enforced at RPC level)
- Unauthorized access (multiple validation gates)

---

**Document Version**: 1.0  
**Status**: Complete ✅

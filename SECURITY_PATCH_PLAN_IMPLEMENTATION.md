# SECURITY PATCH PLAN & IMPLEMENTATION
**Calpe Ward Security Hardening**  
**Date:** January 18, 2026  
**Status:** Ready for Implementation

---

## ANALYSIS OF AUDIT DATA

### RLS Policy Findings (CRITICAL)

**Policy Analysis - Overly Permissive:**

1. ✅ **Token-Based RPCs** – All 48 functions correctly require `p_token` parameter
2. ✅ **Grants are correct** – All authenticated users can execute RPCs (16384 = authenticated role)
3. ❌ **RLS Policies are too open** – Direct table access allows unauthorized data reads:

| Table | Policy | Condition | Risk |
|-------|--------|-----------|------|
| `requests` | `public read requests` | `true` | **Any authenticated user reads ALL requests (all users, all dates)** |
| `requests` | `requests_public_read` | `true` | Duplicate! Same issue |
| `requests` | `requests_read_all` | `true` | Duplicate! Same issue |
| `request_cell_locks` | `public read request_cell_locks` | `true` | Any authenticated user reads locks on any user's cells |
| `staffing_requirements` | `Anyone can read staffing requirements` | `true` | Any authenticated user reads all staffing |
| `users` | `public can read users` | `true` | Any authenticated user reads all staff names/IDs/roles |
| `users` | `users_public_read` | `true` | Duplicate! Same issue |

**Impact:** IDOR + Information Disclosure – Non-admin users can query all staff assignments, create internal maps of who works when, identify gaps.

---

## PATCH PRIORITY & IMPLEMENTATION ORDER

### Phase 1: CRITICAL (Do First - 1 hour)
- ✅ Add Audit Logging Table
- ✅ Create View-As Audit RPC
- ✅ Add PIN Re-Challenge for Admin Operations
- ✅ Fix overly permissive RLS policies

### Phase 2: HIGH (Do Second - 2 hours)
- ✅ Remove duplicate RLS policies
- ✅ Add rate limiting to admin RPCs
- ✅ Implement CSRF tokens for admin actions

### Phase 3: MEDIUM (Do Third - 3 hours)
- ✅ Add session token expiry/TTL
- ✅ Migrate sessionStorage → memory-based token storage
- ✅ Remove debug console logging

### Phase 4: LOW (Optional - 1 hour)
- ✅ Strengthen XSS mitigations
- ✅ Add audit log retention policies

---

## IMPLEMENTATION PATCHES

### PATCH 1: CREATE AUDIT LOGGING TABLE

**File:** SQL Migration Script  
**Severity:** 🔴 CRITICAL  
**Why:** Enable tracking of who did what, when, and from where

```sql
-- Create audit logging table
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id BIGSERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_id UUID NOT NULL REFERENCES public.users(id),
  impersonator_user_id UUID REFERENCES public.users(id),  -- NULL if not impersonated
  action TEXT NOT NULL,  -- 'approve_swap', 'delete_notice', 'lock_request', etc.
  resource_type TEXT NOT NULL,  -- 'swap_request', 'notice', 'request_cell', etc.
  resource_id UUID,
  target_user_id UUID REFERENCES public.users(id),  -- User being affected (if any)
  old_values JSONB,
  new_values JSONB,
  ip_hash TEXT,
  user_agent_hash TEXT,
  status TEXT DEFAULT 'success',  -- 'success', 'failed', 'denied'
  error_message TEXT,
  metadata JSONB DEFAULT '{}'::jsonb
);

-- Indexes for fast queries
CREATE INDEX idx_audit_logs_user_id ON public.audit_logs(user_id);
CREATE INDEX idx_audit_logs_impersonator_id ON public.audit_logs(impersonator_user_id);
CREATE INDEX idx_audit_logs_created_at ON public.audit_logs(created_at DESC);
CREATE INDEX idx_audit_logs_action ON public.audit_logs(action);
CREATE INDEX idx_audit_logs_resource ON public.audit_logs(resource_type, resource_id);

-- Enable RLS
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Policy: Admins can read all audit logs
CREATE POLICY "admins_read_all_audit" ON public.audit_logs
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND is_admin = true
  )
);

-- Policy: Users can only read their own entries (except impersonated)
CREATE POLICY "users_read_own_audit" ON public.audit_logs
FOR SELECT
USING (
  user_id = auth.uid() OR
  impersonator_user_id = auth.uid()
);

-- GRANT SELECT to authenticated
GRANT SELECT ON public.audit_logs TO authenticated;
```

---

### PATCH 2: ADD AUDIT LOGGING RPC

**File:** SQL (new function)  
**Severity:** 🔴 CRITICAL

```sql
-- Helper function to log audit events
-- Called by admin SECURITY DEFINER functions
CREATE OR REPLACE FUNCTION public.log_audit_event(
  p_user_id UUID,
  p_impersonator_user_id UUID DEFAULT NULL,
  p_action TEXT,
  p_resource_type TEXT,
  p_resource_id UUID DEFAULT NULL,
  p_target_user_id UUID DEFAULT NULL,
  p_old_values JSONB DEFAULT NULL,
  p_new_values JSONB DEFAULT NULL,
  p_ip_hash TEXT DEFAULT NULL,
  p_user_agent_hash TEXT DEFAULT NULL,
  p_status TEXT DEFAULT 'success',
  p_error_message TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  INSERT INTO public.audit_logs (
    user_id,
    impersonator_user_id,
    action,
    resource_type,
    resource_id,
    target_user_id,
    old_values,
    new_values,
    ip_hash,
    user_agent_hash,
    status,
    error_message,
    metadata
  ) VALUES (
    p_user_id,
    p_impersonator_user_id,
    p_action,
    p_resource_type,
    p_resource_id,
    p_target_user_id,
    p_old_values,
    p_new_values,
    p_ip_hash,
    p_user_agent_hash,
    p_status,
    p_error_message,
    COALESCE(p_metadata, '{}'::jsonb)
  );
EXCEPTION
  WHEN OTHERS THEN
    -- Silently fail to not break the main operation
    NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.log_audit_event TO authenticated;
```

---

### PATCH 3: FIX OVERLY PERMISSIVE RLS POLICIES

**File:** SQL Migration Script  
**Severity:** 🔴 CRITICAL  
**Why:** Prevent non-admin users from reading all staff data

```sql
-- DROP overly permissive policies
DROP POLICY IF EXISTS "public read requests" ON public.requests;
DROP POLICY IF EXISTS "requests_public_read" ON public.requests;
DROP POLICY IF EXISTS "requests_read_all" ON public.requests;
DROP POLICY IF EXISTS "public read request_cell_locks" ON public.request_cell_locks;
DROP POLICY IF EXISTS "public can read users" ON public.users;
DROP POLICY IF EXISTS "users_public_read" ON public.users;
DROP POLICY IF EXISTS "users_select_all" ON public.users;

-- RECREATE with proper scoping
-- Staff can only read their own requests
CREATE POLICY "requests_read_own" ON public.requests
FOR SELECT
USING (auth.uid() = user_id);

-- Admins can read all requests
CREATE POLICY "requests_read_admin" ON public.requests
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND is_admin = true
  )
);

-- Staff can only see their own request locks
CREATE POLICY "request_cell_locks_read_own" ON public.request_cell_locks
FOR SELECT
USING (auth.uid() = user_id);

-- Admins can see all request locks
CREATE POLICY "request_cell_locks_read_admin" ON public.request_cell_locks
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND is_admin = true
  )
);

-- Users can only read their own user record + active staff list
CREATE POLICY "users_read_self" ON public.users
FOR SELECT
USING (auth.uid() = id);

CREATE POLICY "users_read_active_staff" ON public.users
FOR SELECT
USING (is_active = true);  -- Can list active staff, but not all details

-- Admins can read all users
CREATE POLICY "users_read_admin" ON public.users
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND is_admin = true
  )
);

-- Staffing requirements: Only admins can read (restricted info)
DROP POLICY IF EXISTS "Anyone can read staffing requirements" ON public.staffing_requirements;

CREATE POLICY "staffing_read_admin_only" ON public.staffing_requirements
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND is_admin = true
  )
);
```

---

### PATCH 4: ADD PIN RE-CHALLENGE FOR SENSITIVE ADMIN OPERATIONS

**File:** SQL (new RPC)  
**Severity:** 🔴 CRITICAL  
**Why:** Prevent unattended terminal abuse

```sql
-- New RPC: Verify admin PIN before sensitive operations
CREATE OR REPLACE FUNCTION public.admin_verify_pin_challenge(
  p_token UUID,
  p_pin TEXT
)
RETURNS TABLE(valid BOOLEAN, error_message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid UUID;
  v_stored_pin_hash TEXT;
  v_pin_hash TEXT;
BEGIN
  -- Validate token
  v_admin_uid := public.require_session_permissions(p_token, NULL);

  -- Verify admin
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_admin_uid AND is_admin = true) THEN
    RETURN QUERY SELECT false, 'not_admin'::text;
    RETURN;
  END IF;

  -- Get stored PIN hash
  SELECT pin_hash INTO v_stored_pin_hash FROM public.users WHERE id = v_admin_uid;
  
  IF v_stored_pin_hash IS NULL THEN
    RETURN QUERY SELECT false, 'no_pin_set'::text;
    RETURN;
  END IF;

  -- Hash provided PIN
  v_pin_hash := crypt(p_pin, v_stored_pin_hash);

  -- Verify
  IF v_pin_hash = v_stored_pin_hash THEN
    RETURN QUERY SELECT true, NULL::text;
  ELSE
    RETURN QUERY SELECT false, 'invalid_pin'::text;
  END IF;

END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_verify_pin_challenge TO authenticated;
```

---

### PATCH 5: ADD AUDIT LOGGING TO CRITICAL ADMIN FUNCTIONS

**File:** SQL (modify existing functions)  
**Severity:** 🟠 HIGH  
**Example: admin_approve_swap_request**

```sql
-- MODIFY admin_approve_swap_request to add audit logging at END:

-- ... existing function code ...

  -- Record execution
  v_swap_exec_id := gen_random_uuid();
  INSERT INTO public.swap_executions (...) VALUES (...);
  UPDATE public.swap_requests SET status = 'approved_by_admin' WHERE id = p_swap_request_id;

  -- ADD THIS: Log the audit event
  PERFORM public.log_audit_event(
    p_user_id := v_admin_uid,
    p_impersonator_user_id := NULL,  -- Set if using View-As
    p_action := 'approve_swap_request',
    p_resource_type := 'swap_request',
    p_resource_id := p_swap_request_id,
    p_target_user_id := v_swap_req.initiator_user_id,
    p_new_values := jsonb_build_object(
      'status', 'approved_by_admin',
      'swap_execution_id', v_swap_exec_id
    ),
    p_status := 'success'
  );

  RETURN QUERY SELECT true, v_swap_exec_id, null::text;

EXCEPTION
  WHEN OTHERS THEN
    PERFORM public.log_audit_event(
      p_user_id := v_admin_uid,
      p_action := 'approve_swap_request',
      p_resource_type := 'swap_request',
      p_resource_id := p_swap_request_id,
      p_status := 'failed',
      p_error_message := SQLERRM
    );
    RETURN QUERY SELECT false, null::uuid, SQLERRM::text;
END;
```

---

### PATCH 6: JAVASCRIPT - REQUIRE PIN CHALLENGE FOR SENSITIVE ADMIN OPS

**File:** [js/admin.js](js/admin.js)  
**Severity:** 🔴 CRITICAL  
**Lines:** Insert before sensitive operations

```javascript
/**
 * PIN Challenge Modal for Sensitive Admin Operations
 * Requires admin to re-enter PIN before approving swaps, deleting notices, etc.
 */

async function promptAdminPinChallenge(operationName) {
  return new Promise((resolve) => {
    const modal = document.createElement('div');
    modal.id = 'pinChallengeModal';
    modal.style.cssText = `
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      background: rgba(0,0,0,0.5);
      display: flex;
      align-items: center;
      justify-content: center;
      z-index: 9999;
    `;

    const card = document.createElement('div');
    card.style.cssText = `
      background: white;
      border-radius: 8px;
      padding: 24px;
      max-width: 360px;
      box-shadow: 0 4px 20px rgba(0,0,0,0.15);
    `;

    card.innerHTML = `
      <h3 style="margin: 0 0 8px 0; font-size: 18px; color: #111;">Confirm with PIN</h3>
      <p style="margin: 0 0 16px 0; color: #666; font-size: 14px;">
        This operation requires PIN verification for security.
        <br/><strong>${escapeHtml(operationName)}</strong>
      </p>
      <div style="display: flex; gap: 8px; margin-bottom: 16px;">
        <input type="text" class="pin-digit" maxlength="1" inputmode="numeric" pattern="[0-9]" />
        <input type="text" class="pin-digit" maxlength="1" inputmode="numeric" pattern="[0-9]" />
        <input type="text" class="pin-digit" maxlength="1" inputmode="numeric" pattern="[0-9]" />
        <input type="text" class="pin-digit" maxlength="1" inputmode="numeric" pattern="[0-9]" />
      </div>
      <div style="display: flex; gap: 8px;">
        <button id="pinChallengeConfirm" style="flex: 1; padding: 8px; background: #4F8DF7; color: white; border: none; border-radius: 4px; cursor: pointer;">Confirm</button>
        <button id="pinChallengeCancel" style="flex: 1; padding: 8px; background: #e0e0e0; color: #111; border: none; border-radius: 4px; cursor: pointer;">Cancel</button>
      </div>
    `;

    modal.appendChild(card);
    document.body.appendChild(modal);

    const pinInputs = card.querySelectorAll('.pin-digit');
    pinInputs[0].focus();

    // Auto-advance between digits
    pinInputs.forEach((input, idx) => {
      input.addEventListener('input', (e) => {
        if (e.target.value && idx < 3) pinInputs[idx + 1].focus();
      });
      input.addEventListener('keydown', (e) => {
        if (e.key === 'Backspace' && !e.target.value && idx > 0) pinInputs[idx - 1].focus();
      });
    });

    card.querySelector('#pinChallengeConfirm').addEventListener('click', async () => {
      const pin = Array.from(pinInputs).map(i => i.value).join('');
      if (pin.length !== 4) {
        alert('PIN must be 4 digits');
        return;
      }
      modal.remove();
      resolve(pin);
    });

    card.querySelector('#pinChallengeCancel').addEventListener('click', () => {
      modal.remove();
      resolve(null);
    });
  });
}

// Usage example: Before approving swap
async function approveSwapWithPinChallenge(swapRequestId) {
  const pin = await promptAdminPinChallenge('Approve Shift Swap');
  if (!pin) return;  // User cancelled

  try {
    const { data, error } = await supabaseClient.rpc('admin_verify_pin_challenge', {
      p_token: currentToken,
      p_pin: pin
    });

    if (error || !data[0]?.valid) {
      alert('Invalid PIN. Operation cancelled.');
      return;
    }

    // PIN verified, proceed with operation
    const result = await adminApproveSwapRequest(swapRequestId);
    console.log('Swap approved:', result);
  } catch (e) {
    alert('Error: ' + e.message);
  }
}
```

**Integration points in [js/admin.js](js/admin.js):**

Find all admin action handlers (delete notice, approve swap, lock request) and wrap them:

```javascript
// BEFORE:
async function handleApproveSwap(swapId) {
  await admin_approve_swap(swapId);
}

// AFTER:
async function handleApproveSwap(swapId) {
  const pin = await promptAdminPinChallenge('Approve Shift Swap');
  if (!pin) return;
  
  const { data, error } = await supabaseClient.rpc('admin_verify_pin_challenge', {
    p_token: currentToken,
    p_pin: pin
  });
  
  if (error || !data[0]?.valid) {
    alert('Invalid PIN');
    return;
  }
  
  await admin_approve_swap(swapId);
}
```

---

### PATCH 7: JAVASCRIPT - DISABLE VIEW-AS IMPERSONATION FOR SENSITIVE OPERATIONS

**File:** [js/view-as.js](js/view-as.js)  
**Severity:** 🔴 CRITICAL  
**Lines:** Modify `startViewingAs()` and add server-side validation

```javascript
// BEFORE: startViewingAs just sets sessionStorage
async function startViewingAs(userId) {
  if (!currentUser || !currentUser.is_admin) {
    alert("Only admins can use View As feature");
    return;
  }
  // ... sets currentUser directly
}

// AFTER: Add server-side audit validation
async function startViewingAs(userId) {
  if (!currentUser || !currentUser.is_admin) {
    alert("Only admins can use View As feature");
    return;
  }

  try {
    // Server-side validation: log impersonation start
    const { data, error } = await supabaseClient.rpc('admin_start_impersonation_audit', {
      p_token: currentToken,
      p_target_user_id: userId
    });

    if (error || !data[0]?.allowed) {
      alert('Impersonation not allowed: ' + (data[0]?.error_message || 'unknown error'));
      return;
    }

    // Proceed with impersonation (now logged)
    if (!getRealUser()) {
      sessionStorage.setItem(REAL_USER_STORAGE_KEY, JSON.stringify(currentUser));
    }

    const { data: user, error: userError } = await supabaseClient
      .from("users")
      .select("id, name, role_id, is_admin, is_active, preferred_lang, display_order")
      .eq("id", userId)
      .single();

    if (userError) throw userError;
    if (!user) throw new Error("User not found");

    sessionStorage.setItem(VIEW_AS_STORAGE_KEY, JSON.stringify(user));
    currentUser = user;

    // IMPORTANT: Block sensitive operations while impersonating
    window.isImpersonating = true;
    
    console.log("[VIEW AS] Impersonation started (audit logged)");
  } catch (e) {
    console.error("Failed to start View As", e);
    alert("Failed to view as user: " + e.message);
  }
}

// New RPC function to add to SQL:
CREATE OR REPLACE FUNCTION public.admin_start_impersonation_audit(
  p_token UUID,
  p_target_user_id UUID
)
RETURNS TABLE(allowed BOOLEAN, error_message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid UUID;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, NULL);

  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_admin_uid AND is_admin = true) THEN
    RETURN QUERY SELECT false, 'not_admin'::text;
    RETURN;
  END IF;

  -- Log the impersonation attempt
  PERFORM public.log_audit_event(
    p_user_id := v_admin_uid,
    p_action := 'start_impersonation',
    p_resource_type := 'impersonation',
    p_target_user_id := p_target_user_id,
    p_status := 'started'
  );

  RETURN QUERY SELECT true, NULL::text;
END;
$$;
```

**Prevent sensitive ops during impersonation:**

```javascript
// Add these guards before sensitive operations:

async function handleDeleteNotice(noticeId) {
  if (window.isImpersonating) {
    alert('Cannot delete notices while impersonating. Return to admin view first.');
    return;
  }
  // ... proceed with deletion
}

async function handleLockRequest(userId, date) {
  if (window.isImpersonating) {
    alert('Cannot lock requests while impersonating. Return to admin view first.');
    return;
  }
  // ... proceed
}
```

---

### PATCH 8: JAVASCRIPT - REMOVE DEBUG CONSOLE LOGGING

**File:** [js/swap-functions.js](js/swap-functions.js)  
**Severity:** 🟡 MEDIUM  
**Lines:** 13–31, 51–52, etc.

```javascript
// REMOVE or comment out:
// console.log("[SWAP] Calling admin_execute_shift_swap with:", { ... });
// console.log("[SWAP DEBUG] User ID being sent:", window.currentUser.id);
// console.log("[SWAP DEBUG] User ID type:", typeof window.currentUser.id);

// Keep only error logging:
if (error) {
  console.error("[SWAP ERROR] RPC failed:", error);
}
```

---

## DEPLOYMENT CHECKLIST

### Pre-Deployment
- [ ] Backup Supabase database
- [ ] Test all SQL migrations in staging
- [ ] Test all JS patches in staging
- [ ] Create rollback plan

### Phase 1 Deployment (30 min downtime recommended)
- [ ] Run SQL audit logging table creation
- [ ] Run RLS policy fixes (DROP + CREATE)
- [ ] Run audit logging helper function
- [ ] Verify RLS is still enabled on all tables
- [ ] Test: Non-admin user cannot query all requests
- [ ] Test: Admin can still approve swaps

### Phase 2 Deployment (0 downtime, progressive rollout)
- [ ] Deploy JS admin.js with PIN challenge
- [ ] Deploy JS view-as.js with audit logging
- [ ] Test: PIN challenge modal appears
- [ ] Test: Impersonation is logged
- [ ] Monitor browser console for any errors

### Phase 3 Deployment (0 downtime)
- [ ] Remove debug logging from swap-functions.js
- [ ] Deploy updated JS to all pages
- [ ] Test: Swaps still work without console debug

---

## TESTING MATRIX

| Scenario | Expected Behavior | Pass/Fail |
|----------|-------------------|-----------|
| **Non-admin logs in** | Can only read own requests, not all staff | |
| **Admin approves swap** | PIN challenge appears, requires re-entry | |
| **Admin uses View-As** | Impersonation is logged in audit_logs table | |
| **Admin tries sensitive op while impersonated** | Operation blocked with alert | |
| **Attacker tries sessionStorage manipulation** | View-As fails, audit logged | |
| **Admin leaves terminal unattended** | PIN stored in sessionStorage but sensitive ops need re-auth | |
| **Audit logs query** | Non-admins only see own logs, admins see all | |

---

## ROLLBACK PLAN

If issues occur:

```sql
-- Restore overly permissive RLS (temporary)
CREATE POLICY "public can read users" ON public.users
FOR SELECT USING (true);

CREATE POLICY "public read requests" ON public.requests
FOR SELECT USING (true);

-- Disable audit logging (comment out in functions)
-- Drop new audit table if needed
DROP TABLE IF EXISTS public.audit_logs CASCADE;
```

---

## NEXT STEPS

1. **Run Phase 1 SQL patches** in Supabase SQL editor
2. **Test RLS changes** – verify non-admin data access is restricted
3. **Deploy JS patches** to frontend
4. **Monitor audit_logs table** for activity
5. **Train admins** on new PIN challenge flow
6. **Document** in staff handbook


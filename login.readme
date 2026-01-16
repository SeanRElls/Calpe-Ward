Overview

Current V3 uses a PIN-only modal inside the app, with a soft client-side session
(localStorage + sessionStorage). Admin login additionally writes the PIN to
window.name for cross-page recovery. There is no dedicated login page, so
protected UI and data can render before authentication completes.

The database schema already includes hashed PINs and a sessions table, but
authentication and authorization are inconsistently enforced across client code
and SECURITY DEFINER RPCs.

This document standardizes the login and session model based on existing
schema, without introducing duplicate auth systems.

Key Findings (ordered by severity)

PIN leakage via window.name
window.name is used to persist admin PINs across pages. This value can persist
across navigations and be read in the same window context, leaking credentials
outside the intended page lifecycle.

js/admin.js (setWindowSession, restoreSessionFromWindow)

Client-only auto-login
The app trusts values in localStorage/sessionStorage without server-side session
validation, expiry enforcement, or revocation. If an attacker can set these
values (XSS or shared device), the UI treats the user as authenticated.

js/app.js (STORAGE_KEY restore)

js/admin.js (loadCurrentUser)

Privileged RPCs do not enforce session authentication
Multiple SECURITY DEFINER admin/swap RPCs:

accept p_pin but do not use it, or

check admin/permission state without validating PIN or session token

If a privileged RPC does not validate session token (or validates only
admin/permission flags), then client-side "PIN verified earlier" is not
enforceable and the RPC becomes the real security boundary.

admin_get_swap_requests

admin_get_swap_executions

admin_approve_swap_request

admin_decline_swap_request

admin_execute_shift_swap

admin_get_notice_acks

Inconsistent auth patterns across SQL
Some RPCs check admin-only flags, others check permission groups, others accept
PIN parameters but ignore them. There is no single canonical auth guard across
privileged functions, increasing drift and risk.

Plaintext PIN exposure in browser memory
PINs are stored in sessionStorage in plaintext. While expected in a browser app,
they remain accessible to any injected script on the origin.

js/app.js (setSessionPin)

js/admin.js (sessionStorage PIN writes)

Schema reality vs login flow

users.pin_hash already exists (hashed PINs are in place)

sessions table already exists (token, user_id, created_at, expires_at)

There is no users.username column yet

Sessions are expiry-only (no revocation)

verify_pin_login(p_user_id, p_pin) already issues session tokens (8h expiry)

The login plan must evolve and standardize existing primitives, not create
duplicates.

Constraints and Goals

Dedicated login page using username + PIN

No email requirement; usernames are local identifiers

UI may display username@calpe.local for clarity (display-only)

No protected UI or data should render before auth completes

Remove all PIN storage from window.name

Prefer server-verified session tokens over client-only flags

Permission groups remain the authority for admin features (server-side)

Comprehensive Plan
Phase 0: Inventory and threat modeling

Inventory all SECURITY DEFINER RPCs and privileged tables

Identify which RPCs lack session validation

Identify all client reads from localStorage/sessionStorage

Decide shared-device posture (auto-login vs short-lived sessions)

Phase 1: Database and auth primitives (standardization, not duplication)

Add users.username (unique, lowercased)

Confirm users.pin_hash is used for all users

Remove or replace any plaintext PIN storage (notably admin_pins)

Create/standardize RPC verify_login(p_username, p_pin) that returns a
server-issued session token (and optionally user profile + permission groups).
Do not return "success + user_id" as the primary auth signal.
Prefer evolving/replacing the existing verify_pin_login(p_user_id, p_pin)
(already issues tokens) rather than creating parallel login functions.

Add login rate limiting (table + RPC or RLS guard)

Add login_audit table (user_id, username, ip_hash, user_agent_hash, ts, ok)

PIN validation must occur only at login time to create a session.

Remove p_pin from privileged admin/swap RPCs entirely. PIN verification
happens only at login to issue a session token. All privileged RPCs must
validate session token + permission groups server-side.

Phase 2: Session model (existing table, hardened)

Option A (recommended): Server-issued session tokens

Standardize use of existing sessions table

Add revoked_at (nullable)

Validation must enforce:

expires_at > now()

revoked_at IS NULL (after adding revoked_at).

Create/standardize RPCs:

validate_session(p_token)

revoke_session(p_token)

Store session token in sessionStorage only (not localStorage)

Sessions are the only authentication mechanism post-login.

Phase 2.5: Function canonicalization (critical)

Identify canonical versions of all admin/swap RPCs

Remove, replace, or lock down duplicate/conflicting variants

Restrict permissions to canonical RPCs only

Prevent future auth drift by design

Phase 3: Dedicated login page (confirmed page flow)

index.html becomes the login page (username + PIN)

Current index UI moves to requests.html

rota.html remains the primary authenticated app

Admin users also land on rota.html after login

Accept username input; optionally strip @calpe.local

On success: store session token -> redirect to rota.html

Phase 4: App boot flow

rota.html, requests.html, and admin.html must validate session token
before:

Loading user lists

Fetching rota data

Rendering sensitive UI

Invalid session -> redirect to index.html (login)

Remove PIN modal from app pages or repurpose as a short-lived "unlock for edit"
using a token, not the PIN

Phase 5: Remove window.name PIN flow

Delete setWindowSession / restoreSessionFromWindow

Replace with session-token-based recovery only

Phase 6: Permissions and admin access

Permission groups remain the authority

All admin/swap RPCs must:

Validate session token server-side

Enforce permission groups server-side

UI-based gating is not security

Implement a single canonical auth guard pattern used by all privileged RPCs
for session token validation + permission groups. Every SECURITY DEFINER
admin/swap RPC must use it.

Phase 7: Data and UX hardening

Logout everywhere (revokes session)

Idle timeout (client + server expiry)

Mask PIN input; optionally block paste

Lockout after N failed attempts (username + IP hash)

Display "last login" info from audit table

Phase 8: Migration and rollout

Backfill usernames

Migrate PINs fully to pin_hash

Deploy login page + session hardening

Gate all pages on session validation

Monitor audit logs and error rates

Phase 9: Clean-up and documentation

Update security notes and setup instructions

Document page roles:

index.html = login

rota.html = main app

requests.html = requests

admin.html must never be reachable without session validation

Remove stale references to PIN-only modal

Open Questions

Auto-login on same device? If yes, short server-side expiry (e.g. 8h)

Should rota be readable without login?

Should audit logs be visible to admins in the UI?

Implementation Notes

Username display may show @calpe.local but must not require it

Auth enforcement must be server-side, not UI flags

If "unlock for edit" remains, use a short-lived token, not the PIN

// ============================================================================
// SESSION VALIDATION & TOKEN MANAGEMENT (Phase 4)
// ============================================================================
// Validates session token on page load
// Redirects to login if invalid or expired
// ============================================================================

// Debug logging utility - persists through page reloads
window.DEBUG_LOGS = window.DEBUG_LOGS || [];
function debugLog(msg) {
  console.log(msg);
  window.DEBUG_LOGS.push(msg);
  localStorage.setItem('calpeward_debug_logs', JSON.stringify(window.DEBUG_LOGS.slice(-50))); // Keep last 50
}

const TOKEN_KEY = "calpe_ward_token";
const SESSION_KEY = "calpe_ward_session";
const IMPERSONATION_TOKEN_KEY = "calpeward.impersonationToken";

let currentToken = null;
let supabaseClient = null; // Reuse single Supabase client instance

// Get or create Supabase client
function getSupabaseClient() {
  if (!supabaseClient) {
    supabaseClient = window.supabase.createClient(window.SUPABASE_URL, window.SUPABASE_ANON);
  }
  return supabaseClient;
}

// Get the active token - impersonation token if viewing as, otherwise normal token
function getActiveSessionToken() {
  const impToken = sessionStorage.getItem(IMPERSONATION_TOKEN_KEY);
  if (impToken) return impToken;
  return sessionStorage.getItem(TOKEN_KEY);
}

// Validate session on page load
async function validateSessionOnLoad() {
  // Get token from sessionStorage (prioritize impersonation token)
  const token = getActiveSessionToken();
  debugLog("[SESSION-VALIDATOR] Starting validation, token: " + (token ? "present" : "MISSING"));

  if (!token) {
    // No token - redirect to login
    debugLog("[SESSION-VALIDATOR] No token found, redirecting to login");
    redirectToLogin("Session expired. Please log in again.");
    return false;
  }

  // Store token in memory for RPC calls
  currentToken = token;
  window.currentToken = token;  // Expose globally for RPC calls
  debugLog("[SESSION-VALIDATOR] Token stored globally, validating with server...");

  // Validate token with server
  try {
    const { data, error } = await getSupabaseClient().rpc('validate_session', {
      p_token: token
    });

    if (error || !data || !data[0]?.valid) {
      // Token is invalid or expired
      clearSession();
      redirectToLogin("Session invalid or expired. Please log in again.");
      return false;
    }

    // Token is valid - session can proceed
    return true;

  } catch (err) {
    console.error("Session validation error:", err);
    clearSession();
    redirectToLogin("Could not validate session. Please log in again.");
    return false;
  }
}

// Redirect to login page with optional message
function redirectToLogin(message) {
  clearSession();
  if (message) {
    sessionStorage.setItem('loginMessage', message);
  }
  window.location.href = 'index.html';
}

// Clear all session data
function clearSession() {
  sessionStorage.removeItem(TOKEN_KEY);
  sessionStorage.removeItem(SESSION_KEY);
  sessionStorage.removeItem('loginMessage');
  currentToken = null;
}

// Logout function (called by user action)
async function logout() {
  if (!currentToken) {
    redirectToLogin();
    return;
  }

  try {
    // Revoke session on server
    await getSupabaseClient().rpc('revoke_session', {
      p_token: currentToken
    });
  } catch (err) {
    console.error("Logout error:", err);
  } finally {
    // Clear session regardless of revoke success
    clearSession();
    redirectToLogin("Logged out successfully");
  }
}

// Run validation when page loads (before other scripts)
document.addEventListener('DOMContentLoaded', async () => {
  const isValid = await validateSessionOnLoad();
  if (!isValid) {
    // Prevent other scripts from running
    document.body.innerHTML = '';
  }
});

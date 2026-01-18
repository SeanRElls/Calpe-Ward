// ============================================================================
// SESSION VALIDATION & TOKEN MANAGEMENT (Phase 4)
// ============================================================================
// Validates session token on page load
// Redirects to login if invalid or expired
// ============================================================================

const TOKEN_KEY = "calpe_ward_token";
const SESSION_KEY = "calpe_ward_session";

let currentToken = null;

// Validate session on page load
async function validateSessionOnLoad() {
  // Get token from sessionStorage
  const token = sessionStorage.getItem(TOKEN_KEY);

  if (!token) {
    // No token - redirect to login
    redirectToLogin("Session expired. Please log in again.");
    return false;
  }

  // Store token in memory for RPC calls
  currentToken = token;
  window.currentToken = token;  // Expose globally for RPC calls

  // Initialize Supabase (from config.js)
  const supabaseClient = window.supabase.createClient(window.SUPABASE_URL, window.SUPABASE_ANON);

  // Validate token with server
  try {
    const { data, error } = await supabaseClient.rpc('validate_session', {
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
  window.location.href = '/login.html';
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
    const supabaseClient = window.supabase.createClient(window.SUPABASE_URL, window.SUPABASE_ANON);
    
    // Revoke session on server
    await supabaseClient.rpc('revoke_session', {
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

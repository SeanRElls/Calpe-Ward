/**
 * Permissions Module
 * Handles permission checking for all pages based on user's permission groups
 */

// Debug logging utility - persists through page reloads
window.DEBUG_LOGS = window.DEBUG_LOGS || [];
function debugLog(msg) {
  console.log(msg);
  window.DEBUG_LOGS.push(msg);
  localStorage.setItem('calpeward_debug_logs', JSON.stringify(window.DEBUG_LOGS.slice(-50))); // Keep last 50
}

// Module-scoped variables (not polluting global scope)
(function() {
  let currentUser = null;
  const userPermissions = new Set();

/**
 * Load current user from localStorage and fetch their permissions
 * @returns {Promise<Object|null>} User object or null
 */
async function loadCurrentUserPermissions() {
  const IMPERSONATION_TOKEN_KEY = "calpeward.impersonationToken";
  const VIEW_AS_STORAGE_KEY = "calpeward.viewAs";
  
  // Check if we're in impersonation mode
  const impersonationToken = sessionStorage.getItem(IMPERSONATION_TOKEN_KEY);
  const viewAsUser = sessionStorage.getItem(VIEW_AS_STORAGE_KEY);
  const token = impersonationToken || window.currentToken || sessionStorage.getItem("calpe_ward_token");

  debugLog("[PERMISSIONS] Starting loadCurrentUserPermissions, token: " + (token ? "present" : "MISSING"));

  if (!token) {
    debugLog("[PERMISSIONS] No session token available");
    return null;
  }

  try {
    // Load user profile via token-only RPC
    debugLog("[PERMISSIONS] Calling rpc_get_current_user...");
    const { data: profileRows, error: profileError } = await window.supabaseClient
      .rpc("rpc_get_current_user", { p_token: token });

    debugLog("[PERMISSIONS] rpc_get_current_user response: profileRows=" + JSON.stringify(profileRows) + " error=" + JSON.stringify(profileError));

    const profile = Array.isArray(profileRows) ? profileRows[0] : profileRows;

    if (profileError || !profile) {
      debugLog("[PERMISSIONS] Failed to load user profile - error: " + JSON.stringify(profileError) + " profile: " + JSON.stringify(profile));
      return null;
    }

    currentUser = profile;
    debugLog("[PERMISSIONS] Loaded user: " + profile.name + " id: " + profile.id + " is_admin: " + profile.is_admin);

    // If admin, skip permission loading (admins have all permissions)
    if (profile.is_admin) {
      debugLog("[PERMISSIONS] User is admin - has all permissions");
      localStorage.setItem("calpeward.loggedInUserId", profile.id);
      return profile;
    }

    // Load permissions via token-only RPC
    debugLog("[PERMISSIONS] Calling rpc_get_user_permissions...");
    const { data: perms, error: permsError } = await window.supabaseClient
      .rpc("rpc_get_user_permissions", { p_token: token });

    debugLog("[PERMISSIONS] rpc_get_user_permissions response: perms=" + JSON.stringify(perms) + " error=" + JSON.stringify(permsError));

    if (permsError) {
      debugLog("[PERMISSIONS] Failed to load permissions: " + JSON.stringify(permsError));
    } else {
      userPermissions.clear();
      (perms || []).forEach(p => {
        if (p.permission_key) {
          userPermissions.add(p.permission_key);
        }
      });
      debugLog("[PERMISSIONS] Loaded permissions: " + JSON.stringify(Array.from(userPermissions)));
    }

    localStorage.setItem("calpeward.loggedInUserId", profile.id);
    debugLog("[PERMISSIONS] Successfully loaded user and permissions");

    return profile;
  } catch (e) {
    debugLog("[PERMISSIONS] Error loading user permissions: " + e.message + " stack: " + e.stack);
    return null;
  }
}

/**
 * Check if current user has a specific permission
 * @param {string} key - Permission key (e.g., "rota.view_draft")
 * @returns {boolean} True if user has permission
 */
function hasPermission(key) {
  if (!currentUser) return false;
  if (currentUser.is_admin) return true;
  return userPermissions.has(key);
}

/**
 * Require a permission or show alert
 * @param {string} key - Permission key
 * @param {string} msg - Optional custom message
 * @returns {boolean} True if user has permission
 */
function requirePermission(key, msg) {
  if (hasPermission(key)) return true;
  alert(msg || "You don't have permission to perform this action.");
  return false;
}

/**
 * Get current user object
 * @returns {Object|null} Current user or null
 */
function getCurrentUser() {
  return currentUser;
}

/**
 * Check if current user is admin
 * @returns {boolean} True if admin
 */
function isAdmin() {
  return currentUser?.is_admin === true;
}

  // Export for use in other scripts
  if (typeof window !== 'undefined') {
    window.PermissionsModule = {
      loadCurrentUserPermissions,
      hasPermission,
      requirePermission,
      getCurrentUser,
      isAdmin
    };
  }
})();

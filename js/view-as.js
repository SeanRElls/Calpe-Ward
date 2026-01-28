/* =========================================================
   VIEW AS FEATURE - SUPERADMIN Full Impersonation
   ========================================================= */

const VIEW_AS_STORAGE_KEY = "calpeward.viewAs";
const REAL_USER_STORAGE_KEY = "calpeward.realUser";
const REAL_TOKEN_STORAGE_KEY = "calpeward.realToken";
// IMPERSONATION_TOKEN_KEY is defined in session-validator.js

function getTokenStorageKey() {
  return (typeof TOKEN_KEY !== "undefined" && TOKEN_KEY) ? TOKEN_KEY : "calpe_ward_token";
}

// Get the active token - impersonation token if viewing as, otherwise real token
function getActiveToken() {
  const impToken = sessionStorage.getItem("calpeward.impersonationToken");
  if (impToken) return impToken;
  return sessionStorage.getItem(getTokenStorageKey());
}

function roleNameFromId(roleId) {
  if (roleId === 1) return "Charge Nurses";
  if (roleId === 2) return "Staff Nurses";
  if (roleId === 3) return "Nursing Assistants";
  return "Unknown";
}

function getRealUser() {
  const stored = sessionStorage.getItem(REAL_USER_STORAGE_KEY);
  if (stored) {
    try { return JSON.parse(stored); } catch (e) { return null; }
  }
  return null;
}

function getViewAsUser() {
  const stored = sessionStorage.getItem(VIEW_AS_STORAGE_KEY);
  if (stored) {
    try { return JSON.parse(stored); } catch (e) { return null; }
  }
  return null;
}

function ensureViewAsBanner() {
  let banner = document.getElementById("viewAsBanner");
  if (banner) return banner;

  // Add global style for select options
  if (!document.getElementById("viewAsDropdownStyles")) {
    const style = document.createElement("style");
    style.id = "viewAsDropdownStyles";
    style.textContent = `
      #viewAsSelectorBanner {
        appearance: none;
        -webkit-appearance: none;
        -moz-appearance: none;
        background-image: url("data:image/svg+xml;charset=UTF-8,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3e%3cpolyline points='6 9 12 15 18 9'%3e%3c/polyline%3e%3c/svg%3e");
        background-repeat: no-repeat;
        background-position: right 8px center;
        background-size: 16px;
        padding-right: 32px;
      }
      #viewAsSelectorBanner option {
        background-color: #5a67d8 !important;
        color: white !important;
        padding: 8px !important;
      }
      #viewAsSelectorBanner optgroup {
        background-color: #4c51bf !important;
        color: white !important;
        font-weight: bold !important;
      }
    `;
    document.head.appendChild(style);
  }

  banner = document.createElement("div");
  banner.id = "viewAsBanner";
  banner.style.cssText = `
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 12px 20px;
    text-align: center;
    font-weight: 600;
    font-size: 15px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.15);
    z-index: 99999;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 16px;
  `;

  const viewAsUser = getViewAsUser();
  const realUser = getRealUser();

  if (viewAsUser && realUser) {
    // Already viewing as someone - show active impersonation banner
    const message = document.createElement("span");
    message.textContent = `🔒 Viewing as ${viewAsUser.name}`;
    message.style.cssText = "flex: 1; text-align: center; font-size: 16px;";

    const changeUserBtn = document.createElement("button");
    changeUserBtn.textContent = "Change User";
    changeUserBtn.style.cssText = `
      background: rgba(255,255,255,0.2);
      color: white;
      border: 1px solid rgba(255,255,255,0.3);
      padding: 8px 16px;
      border-radius: 6px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s;
      margin-right: 8px;
    `;
    changeUserBtn.onmouseover = () => changeUserBtn.style.background = "rgba(255,255,255,0.3)";
    changeUserBtn.onmouseout = () => changeUserBtn.style.background = "rgba(255,255,255,0.2)";
    changeUserBtn.onclick = () => {
      console.log("[VIEW-AS] Change user clicked - restoring admin then showing selector");
      
      // Restore admin session
      const realUserData = getRealUser();
      const realToken = sessionStorage.getItem(REAL_TOKEN_STORAGE_KEY);
      
      if (realUserData && realToken) {
        // Clear impersonation
        sessionStorage.removeItem("calpeward.viewAs");
        sessionStorage.removeItem("calpeward.impersonationToken");
        
        // Restore admin token
        sessionStorage.setItem(getTokenStorageKey(), realToken);
        sessionStorage.setItem("calpe_ward_user", JSON.stringify(realUserData));
        localStorage.setItem("calpeward.loggedInUserId", realUserData.id);
        
        // Don't clear realUser/realToken - keep them so we can impersonate again
        // Just reload - the View As button will appear
        window.location.reload();
      } else {
        console.error("[VIEW-AS] No real user/token to restore");
        stopViewingAs();
      }
    };

    const returnBtn = document.createElement("button");
    returnBtn.textContent = "Return to Admin Account";
    returnBtn.style.cssText = `
      background: white;
      color: #667eea;
      border: none;
      padding: 8px 16px;
      border-radius: 6px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s;
    `;
    returnBtn.onmouseover = () => returnBtn.style.background = "#f0f0f0";
    returnBtn.onmouseout = () => returnBtn.style.background = "white";
    returnBtn.onclick = () => stopViewingAs();

    banner.appendChild(message);
    banner.appendChild(changeUserBtn);
    banner.appendChild(returnBtn);
  } else {
    // Not viewing as anyone - show selector
    const label = document.createElement("span");
    label.textContent = "👁️ SUPERADMIN View As:";
    label.style.marginRight = "12px";

    const selector = document.createElement("select");
    selector.id = "viewAsSelectorBanner";
    selector.style.cssText = `
      background-color: #5a67d8;
      color: white;
      border: 2px solid rgba(255,255,255,0.3);
      border-radius: 6px;
      padding: 8px 32px 8px 12px;
      font-size: 14px;
      font-weight: 500;
      cursor: pointer;
      min-width: 500px;
      max-width: 600px;
    `;

    const defaultOpt = document.createElement("option");
    defaultOpt.value = "";
    defaultOpt.textContent = "Select a user to impersonate...";
    defaultOpt.style.cssText = "background-color: #5a67d8; color: white; padding: 8px;";
    selector.appendChild(defaultOpt);

    selector.onchange = (e) => {
      if (e.target.value) {
        startViewingAs(e.target.value);
      }
    };

    banner.appendChild(label);
    banner.appendChild(selector);
  }

  document.body.insertBefore(banner, document.body.firstChild);

  // Adjust body padding to account for banner
  const currentPadding = parseInt(window.getComputedStyle(document.body).paddingTop) || 0;
  document.body.style.paddingTop = (currentPadding + 60) + "px";

  return banner;
}

function removeViewAsBanner() {
  const banner = document.getElementById("viewAsBanner");
  if (banner) {
    const currentPadding = parseInt(window.getComputedStyle(document.body).paddingTop) || 0;
    document.body.style.paddingTop = Math.max(0, currentPadding - 60) + "px";
    banner.remove();
  }
}

async function buildOptions(allUsers, supabaseClient) {
  if (!allUsers || !Array.isArray(allUsers)) return;

  const selector = document.getElementById("viewAsSelectorBanner");
  if (!selector) return;

  // Clear existing options except first
  while (selector.options.length > 1) {
    selector.remove(1);
  }

  // Group by role
  const byRole = {};
  allUsers.forEach(u => {
    const roleName = u.role_name || "Unknown";
    if (!byRole[roleName]) byRole[roleName] = [];
    byRole[roleName].push(u);
  });

  // Sort role names
  const roleNames = Object.keys(byRole).sort();

  roleNames.forEach(roleName => {
    const optgroup = document.createElement("optgroup");
    optgroup.label = roleName;
    optgroup.style.cssText = "background-color: #4c51bf; color: white; font-weight: bold;";

    const users = byRole[roleName].sort((a, b) => a.name.localeCompare(b.name));
    users.forEach(user => {
      const opt = document.createElement("option");
      opt.value = user.id;
      opt.textContent = `${user.name}${user.is_active ? '' : ' (inactive)'}`;
      opt.style.cssText = "background-color: #5a67d8; color: white; padding: 8px;";
      optgroup.appendChild(opt);
    });

    selector.appendChild(optgroup);
  });
}

async function startViewingAs(targetUserId) {
  const supaClient = window.supabaseClient || window.supabase;
  if (!supaClient) {
    alert("Supabase client not available");
    return;
  }

  const adminToken = sessionStorage.getItem(getTokenStorageKey());
  if (!adminToken) {
    alert("No admin token found");
    return;
  }

  // Get target user details
  const { data: users, error: userError } = await supaClient.rpc("admin_get_user_by_id", {
    p_token: adminToken,
    p_user_id: targetUserId
  });

  console.log("[VIEW-AS] admin_get_user_by_id response:", { users, userError });

  if (userError) {
    console.error("[VIEW-AS] Error getting user:", userError);
    alert(`Failed to get user details: ${userError.message}`);
    return;
  }

  if (!users || users.length === 0) {
    console.error("[VIEW-AS] User not found:", targetUserId);
    alert(`User not found with ID: ${targetUserId}`);
    return;
  }

  const targetUser = users[0];

  // Call admin_impersonate_user RPC
  console.log("Calling admin_impersonate_user...", { targetUserId });
  const { data, error } = await supaClient.rpc("admin_impersonate_user", {
    p_admin_token: adminToken,
    p_target_user_id: targetUserId,
    p_ttl_hours: 12
  });

  if (error) {
    console.error("Impersonation failed:", error);
    alert(`Impersonation failed: ${error.message}`);
    return;
  }

  if (!data || data.length === 0) {
    alert("No impersonation token returned");
    return;
  }

  const result = data[0];
  if (result.error_message) {
    alert(`Impersonation error: ${result.error_message}`);
    return;
  }

  if (!result.impersonation_token) {
    alert("No impersonation token in response");
    return;
  }

  console.log("Impersonation successful", { token: result.impersonation_token.slice(0, 8) + "..." });

  // Store original admin context
  const currentUser = window.currentUser || JSON.parse(sessionStorage.getItem("calpe_ward_user") || "null");
  sessionStorage.setItem(REAL_USER_STORAGE_KEY, JSON.stringify(currentUser));
  sessionStorage.setItem(REAL_TOKEN_STORAGE_KEY, adminToken);

  // Store impersonation context
  sessionStorage.setItem(VIEW_AS_STORAGE_KEY, JSON.stringify(targetUser));
  sessionStorage.setItem("calpeward.impersonationToken", result.impersonation_token);

  // Update current user to target user
  sessionStorage.setItem("calpe_ward_user", JSON.stringify(targetUser));
  if (window.currentUser) {
    window.currentUser = targetUser;
  }

  // Reload page to apply impersonation
  window.location.reload();
}

function stopViewingAs() {
  console.log("[VIEW-AS] Stopping impersonation, returning to admin");
  
  const realUser = getRealUser();
  const realToken = sessionStorage.getItem(REAL_TOKEN_STORAGE_KEY);

  if (!realUser || !realToken) {
    console.error("[VIEW-AS] No real user/token stored - clearing all and redirecting to login");
    // Clear everything and redirect to login
    sessionStorage.clear();
    localStorage.clear();
    window.location.href = "login.html";
    return;
  }

  console.log("[VIEW-AS] Restoring admin user:", realUser.name);

  // Clear impersonation context
  sessionStorage.removeItem(VIEW_AS_STORAGE_KEY);
  sessionStorage.removeItem("calpeward.impersonationToken");
  sessionStorage.removeItem(REAL_USER_STORAGE_KEY);
  sessionStorage.removeItem(REAL_TOKEN_STORAGE_KEY);

  // Restore admin context in sessionStorage
  sessionStorage.setItem(getTokenStorageKey(), realToken);
  sessionStorage.setItem("calpe_ward_user", JSON.stringify(realUser));
  
  // Restore admin ID in localStorage
  localStorage.setItem("calpeward.loggedInUserId", realUser.id);
  
  if (window.currentUser) {
    window.currentUser = realUser;
  }

  console.log("[VIEW-AS] Admin restored, reloading page");

  // Remove banner and reload
  removeViewAsBanner();
  window.location.reload();
}

// Helper function to clear stuck impersonation (call from console if needed)
window.clearStuckImpersonation = function() {
  console.log("[VIEW-AS] Clearing stuck impersonation");
  sessionStorage.removeItem("calpeward.viewAs");
  sessionStorage.removeItem("calpeward.impersonationToken");
  sessionStorage.removeItem("calpeward.realUser");
  sessionStorage.removeItem("calpeward.realToken");
  window.location.reload();
};

async function initViewAs(supabaseClient, currentUser) {
  const viewAsUser = getViewAsUser();
  const realUser = getRealUser();

  // If actively viewing as someone, ALWAYS show the banner (even if current user is not admin)
  if (viewAsUser && realUser) {
    console.log("[VIEW-AS] Active impersonation detected, showing banner");
    ensureViewAsBanner();
    return;
  }

  // Only show for superadmin (is_admin = true)
  if (!currentUser || !currentUser.is_admin) {
    console.log("[VIEW-AS] Not admin, skipping init");
    return;
  }

  console.log("[VIEW-AS] Initializing for admin:", currentUser.name);

  // If View As button clicked, show selector banner
  const viewAsBtn = document.getElementById("viewAsBtn");
  if (viewAsBtn) {
    console.log("[VIEW-AS] Adding click handler to View As button");
    viewAsBtn.addEventListener("click", async (e) => {
      e.preventDefault();
      console.log("[VIEW-AS] Button clicked");
      
      const banner = ensureViewAsBanner();
      
      // Load all users for selector
      console.log("[VIEW-AS] Loading users...");
      const { data: allUsers, error } = await supabaseClient.rpc("admin_get_users", {
        p_token: getActiveToken(),
        p_include_inactive: true
      });

      if (error) {
        console.error("[VIEW-AS] Failed to load users:", error);
        return;
      }

      console.log("[VIEW-AS] Loaded", allUsers.length, "users");

      const usersWithRoles = allUsers.map(u => ({
        ...u,
        role_name: roleNameFromId(u.role_id)
      }));

      await buildOptions(usersWithRoles, supabaseClient);
    });
  } else {
    console.warn("[VIEW-AS] View As button not found in DOM");
  }
}

// Expose globally so pages can call it
window.initViewAs = initViewAs;

// Auto-init with retry logic (max 50 retries = 5 seconds)
let retryCount = 0;
const MAX_RETRIES = 50;

function tryInitViewAs() {
  const supabaseClient = window.supabaseClient || window.supabase;
  const currentUser = window.currentUser;
  
  if (supabaseClient && currentUser) {
    console.log("[VIEW-AS] Initializing - supabase:", !!supabaseClient, "currentUser:", currentUser.name);
    initViewAs(supabaseClient, currentUser);
  } else if (retryCount < MAX_RETRIES) {
    retryCount++;
    // Retry after a short delay if user not loaded yet
    setTimeout(tryInitViewAs, 100);
  } else {
    console.warn("[VIEW-AS] Max retries reached - supabase:", !!supabaseClient, "currentUser:", !!currentUser);
  }
}

// Auto-init on DOMContentLoaded
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", tryInitViewAs);
} else {
  tryInitViewAs();
}

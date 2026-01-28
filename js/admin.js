    console.log("[ADMIN.JS] Script loaded");

    // Utility function for debouncing
    function debounce(func, delay) {
      let timeoutId;
      return function(...args) {
        clearTimeout(timeoutId);
        timeoutId = setTimeout(() => func(...args), delay);
      };
    }

    const navLinks = Array.from(document.querySelectorAll(".nav a[data-panel]"));
    const panels = Array.from(document.querySelectorAll(".panel"));
    const adminUserAuthNotice = document.getElementById("adminUserAuthNotice");

    let currentUser = null;
    let adminUsersCache = [];
    let adminEditingUserId = null;
    let usersLoaded = false;
    let userPermissions = new Set();

    const adminUsersList = document.getElementById("adminUsersList");
    const adminAddUserBtn = document.getElementById("adminAddUserBtn");
    const adminUserSearch = document.getElementById("adminUserSearch");
    const adminShowInactiveUsers = document.getElementById("adminShowInactiveUsers");
    const adminLoginUser = document.getElementById("adminLoginUser");
    const adminLoginPin = document.getElementById("adminLoginPin");
    const adminLoginBtn = document.getElementById("adminLoginBtn");
    const adminLoginMsg = document.getElementById("adminLoginMsg");
    const adminEditUserName = document.getElementById("adminEditUserName");
    const adminEditUserRole = document.getElementById("adminEditUserRole");
    const adminEditUserPin = document.getElementById("adminEditUserPin");
    const adminCancelUserEditBtn = document.getElementById("adminCancelUserEditBtn");
    const adminUserEditHelp = document.getElementById("adminUserEditHelp");
    const adminPrefShiftClustering = document.getElementById("adminPrefShiftClustering");
    const adminPrefNightAppetite = document.getElementById("adminPrefNightAppetite");
    const adminPrefWeekendAppetite = document.getElementById("adminPrefWeekendAppetite");
    const adminPrefLeaveAdjacency = document.getElementById("adminPrefLeaveAdjacency");
    const adminPrefShiftClusteringValue = document.getElementById("adminPrefShiftClusteringValue");
    const adminPrefNightAppetiteValue = document.getElementById("adminPrefNightAppetiteValue");
    const adminPrefWeekendAppetiteValue = document.getElementById("adminPrefWeekendAppetiteValue");
    const adminPrefLeaveAdjacencyValue = document.getElementById("adminPrefLeaveAdjacencyValue");
    const adminCanBeInChargeDay = document.getElementById("adminCanBeInChargeDay");
    const adminCanBeInChargeNight = document.getElementById("adminCanBeInChargeNight");
    const adminCannotBeSecondDay = document.getElementById("adminCannotBeSecondDay");
    const adminCannotBeSecondNight = document.getElementById("adminCannotBeSecondNight");
    const adminCanWorkNights = document.getElementById("adminCanWorkNights");
    const adminPrefsHelp = document.getElementById("adminPrefsHelp");
    const adminEditUserSearch = document.getElementById("adminEditUserSearch");
    const adminEditUserSelect = document.getElementById("adminEditUserSelect");
    const adminAddUserName = document.getElementById("adminAddUserName");
    const adminAddUserRole = document.getElementById("adminAddUserRole");
    const adminAddUserPin = document.getElementById("adminAddUserPin");
    const adminCreateUserBtn = document.getElementById("adminCreateUserBtn");
    const adminAddUserCancelBtn = document.getElementById("adminAddUserCancelBtn");
    const adminUserAddHelp = document.getElementById("adminUserAddHelp");
    const adminUsersReorderList = document.getElementById("adminUsersReorderList");
    const usersPages = Array.from(document.querySelectorAll(".users-page"));
    const usersPageTabs = Array.from(document.querySelectorAll(".subtab[data-users-page]"));
    const shiftsPages = Array.from(document.querySelectorAll(".shifts-page"));
    const shiftsPageTabs = Array.from(document.querySelectorAll(".subtab[data-shifts-page]"));
    const swapsPages = Array.from(document.querySelectorAll(".swaps-page"));
    const swapsPageTabs = Array.from(document.querySelectorAll(".subtab[data-swaps-page]"));
    const adminUserPermissionGroups = document.getElementById("adminUserPermissionGroups");
    const adminUserStatus = document.getElementById("adminUserStatus");
    const permissionGroupSelect = document.getElementById("permissionGroupSelect");
    const permissionGroupName = document.getElementById("permissionGroupName");
    const createPermissionGroupBtn = document.getElementById("createPermissionGroupBtn");
    const permissionGroupHelp = document.getElementById("permissionGroupHelp");
    const permissionsMatrix = document.getElementById("permissionsMatrix");
    // Non-staff admin elements
    const nsList = document.getElementById("nsList");
    const nsShowInactive = document.getElementById("nsShowInactive");
    const nsSearchInput = document.getElementById("nsSearchInput");
    const nsFilterCategory = document.getElementById("nsFilterCategory");
    const nsFilterRole = document.getElementById("nsFilterRole");
    const nsRefreshBtn = document.getElementById("nsRefreshBtn");
    const nsPageTabs = Array.from(document.querySelectorAll('.subtab[data-ns-page]'));
    const nsPages = [
      document.getElementById('nsPageView'),
      document.getElementById('nsPageAdd'),
      document.getElementById('nsPageEdit')
    ].filter(Boolean);
    const nsAddName = document.getElementById('nsAddName');
    const nsAddCategory = document.getElementById('nsAddCategory');
    const nsAddRole = document.getElementById('nsAddRole');
    const nsAddNotes = document.getElementById('nsAddNotes');
    const nsCreateBtn = document.getElementById('nsCreateBtn');
    const nsAddClearBtn = document.getElementById('nsAddClearBtn');
    const nsAddHelp = document.getElementById('nsAddHelp');
    const nsEditSearch = document.getElementById('nsEditSearch');
    const nsEditSelect = document.getElementById('nsEditSelect');
    const nsEditName = document.getElementById('nsEditName');
    const nsEditCategory = document.getElementById('nsEditCategory');
    const nsEditRole = document.getElementById('nsEditRole');
    const nsEditNotes = document.getElementById('nsEditNotes');
    const nsSaveBtn = document.getElementById('nsSaveBtn');
    const nsEditCancelBtn = document.getElementById('nsEditCancelBtn');
    const nsEditHelp = document.getElementById('nsEditHelp');
    const nsToggleActiveBtn = document.getElementById('nsToggleActiveBtn');
    let nsCache = [];
    let nsEditingId = null;

    // Bank holidays elements
    const bhYear = document.getElementById('bhYear');
    const bhDate = document.getElementById('bhDate');
    const bhName = document.getElementById('bhName');
    const bhAddBtn = document.getElementById('bhAddBtn');
    const bhAddHelp = document.getElementById('bhAddHelp');
    const bhList = document.getElementById('bhList');
    let bhCache = [];

    function escapeHtml(str){
      return String(str || "")
        .replaceAll("&","&amp;")
        .replaceAll("<","&lt;")
        .replaceAll(">","&gt;")
        .replaceAll("\"","&quot;")
        .replaceAll("'","&#039;");
    }

    function getAdminToken(){
      const token = window.currentToken || sessionStorage.getItem("calpe_ward_token");
      if (!token) {
        throw new Error("No session token available for admin panel.");
      }
      return token;
    }

    function pinKey(userId){ return `calpeward.pin.${userId}`; }

    async function requireAdminPin(){
      const ok = await promptAdminPinChallenge();
      if (!ok) {
        throw new Error("PIN verification failed.");
      }
    }

    // SECURITY PATCH: PIN Challenge for sensitive admin operations
    async function promptAdminPinChallenge() {
      return new Promise((resolve) => {
        const modal = document.createElement("div");
        modal.id = "adminPinChallengeModal";
        modal.style.cssText = `
          position: fixed; top: 0; left: 0; right: 0; bottom: 0;
          background: rgba(0,0,0,0.5); display: flex; align-items: center;
          justify-content: center; z-index: 10001; font-family: sans-serif;
        `;
        modal.innerHTML = `
          <div style="
            background: white; padding: 24px; border-radius: 8px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3); max-width: 400px;
            text-align: center;
          ">
            <h3 style="margin: 0 0 12px 0; color: #333;">Verify Admin PIN</h3>
            <p style="margin: 0 0 16px 0; color: #666; font-size: 14px;">
              This is a sensitive operation. Please enter your 4-digit PIN to continue.
            </p>
            <input type="password" id="adminPinInput" maxlength="4" placeholder="0000"
              inputmode="numeric" pattern="[0-9]*"
              style="
                width: 100%; padding: 10px; font-size: 16px; letter-spacing: 4px;
                text-align: center; border: 1px solid #ddd; border-radius: 4px;
                box-sizing: border-box; margin-bottom: 16px;
              " />
            <div style="display: flex; gap: 8px;">
              <button id="adminPinCancel" style="
                flex: 1; padding: 10px; border: 1px solid #ddd; background: #f5f5f5;
                border-radius: 4px; cursor: pointer; font-weight: 500;
              ">Cancel</button>
              <button id="adminPinConfirm" style="
                flex: 1; padding: 10px; border: none; background: #667eea; color: white;
                border-radius: 4px; cursor: pointer; font-weight: 500;
              ">Verify</button>
            </div>
          </div>
        `;
        document.body.appendChild(modal);
        
        const input = modal.querySelector("#adminPinInput");
        input.focus();
        
        const cleanup = () => {
          modal.remove();
        };
        
        modal.querySelector("#adminPinCancel").addEventListener("click", () => {
          cleanup();
          resolve(false);
        });
        
        modal.querySelector("#adminPinConfirm").addEventListener("click", () => {
          const enteredPin = input.value;
          cleanup();
          resolve(enteredPin);
        });
        
        input.addEventListener("keypress", (e) => {
          if (e.key === "Enter") {
            modal.querySelector("#adminPinConfirm").click();
          }
        });
      }).then(async (enteredPin) => {
        if (!enteredPin || !/^\d{4}$/.test(String(enteredPin))) {
          alert("PIN must be 4 digits.");
          return false;
        }

        try {
          const { data, error } = await supabaseClient.rpc("admin_verify_pin_challenge", {
            p_token: currentToken,
            p_pin: String(enteredPin)
          });

          if (error) throw error;

          const result = Array.isArray(data) ? data[0] : data;
          if (!result?.valid) {
            alert("Invalid PIN.");
            return false;
          }

          return true;
        } catch (err) {
          console.error("PIN verification failed:", err);
          alert("PIN verification failed.");
          return false;
        }
      });
    }

    async function loadCurrentUser(){
      console.log("[SESSION DEBUG] loadCurrentUser: starting");
      const savedId = localStorage.getItem(STORAGE_KEY);
      console.log("[SESSION DEBUG] loadCurrentUser: savedId from localStorage=", savedId);
      let token = null;
      try {
        token = getAdminToken();
      } catch (e) {
        token = null;
      }
      if (!savedId || !token){
        console.log("[SESSION DEBUG] No savedId, showing auth notice");
        adminUserAuthNotice.style.display = "block";
        updateUserStatus(null);
        return null;
      }
      const { data, error } = await supabaseClient.rpc("rpc_get_current_user", {
        p_token: token
      });
      const user = Array.isArray(data) ? data[0] : data;
      if (error || !user){
        adminUserAuthNotice.style.display = "block";
        updateUserStatus(null);
        return null;
      }
      currentUser = user;
      window.currentUser = currentUser; // Expose to window for other scripts
      await loadUserPermissions();
      if (!hasPermission("system.admin_panel")){
        adminUserAuthNotice.style.display = "block";
        updateUserStatus(currentUser, false);
        return null;
      }
      adminUserAuthNotice.style.display = "none";
      updateUserStatus(currentUser, true);
      applyPermissionUI();
      return currentUser;
    }

    async function loadLoginUsers(){
      if (!adminLoginUser) return;
      try {
        const cachedRaw = localStorage.getItem("calpeward.users_cache");
        const cachedUsers = cachedRaw ? JSON.parse(cachedRaw) : [];
        const { data: users, error } = await supabaseClient.rpc("admin_get_users", {
          p_token: getAdminToken(),
          p_include_inactive: true
        });
        if (error) throw error;
        const sourceUsers = (users && users.length) ? users : cachedUsers;

        let options = (sourceUsers || [])
          .filter(u => u.is_active !== false)
          .filter(u => u.is_admin)
          .map(u => `<option value="${escapeHtml(u.id)}">${escapeHtml(u.name)}</option>`)
          .join("");

        if (!options) {
          options = (sourceUsers || [])
            .filter(u => u.is_active !== false)
            .map(u => `<option value="${escapeHtml(u.id)}">${escapeHtml(u.name)}</option>`)
            .join("");
          if (adminLoginMsg) adminLoginMsg.textContent = "No admin users found. Showing all active users.";
        } else if (adminLoginMsg) {
          adminLoginMsg.textContent = "";
        }

        adminLoginUser.innerHTML = `<option value="">Select user...</option>${options}`;
      } catch (e) {
        console.warn("Failed to load login users", e);
        const cachedRaw = localStorage.getItem("calpeward.users_cache");
        const cachedUsers = cachedRaw ? JSON.parse(cachedRaw) : [];
        if (cachedUsers.length) {
          const options = cachedUsers
            .filter(u => u.is_active !== false)
            .map(u => `<option value="${escapeHtml(u.id)}">${escapeHtml(u.name)}</option>`)
            .join("");
          adminLoginUser.innerHTML = `<option value="">Select user...</option>${options}`;
          if (adminLoginMsg) adminLoginMsg.textContent = "Loaded from cached users.";
        } else {
          adminLoginUser.innerHTML = `<option value="">Unable to load users</option>`;
        }
      }
    }

    async function adminLogin(){
      if (!adminLoginUser || !adminLoginPin) return;
      const userId = adminLoginUser.value;
      const pin = (adminLoginPin.value || "").trim();
      if (!userId) {
        if (adminLoginMsg) adminLoginMsg.textContent = "Select a user.";
        return;
      }
      if (!/^\d{4}$/.test(pin)) {
        if (adminLoginMsg) adminLoginMsg.textContent = "Enter a 4-digit PIN.";
        return;
      }
      if (adminLoginMsg) adminLoginMsg.textContent = "Signing in...";
      try {
        const { data: ok, error: vErr } = await supabaseClient.rpc("admin_verify_user_pin", {
          p_token: currentToken,
          p_target_user_id: userId,
          p_pin: pin
        });
        if (vErr) throw vErr;
        if (!ok) {
          if (adminLoginMsg) adminLoginMsg.textContent = "Invalid PIN.";
          return;
        }
        const { data: userRows, error } = await supabaseClient.rpc("admin_get_user_by_id", {
          p_token: currentToken,
          p_user_id: userId
        });
        const user = Array.isArray(userRows) ? userRows[0] : userRows;
        if (error || !user) throw error || new Error("User not found");
        localStorage.setItem(STORAGE_KEY, user.id);
        sessionStorage.removeItem(pinKey(user.id));
        currentUser = user;
        window.currentUser = currentUser; // Expose to window for other scripts
        await loadUserPermissions();
        const canAccess = hasPermission("system.admin_panel");
        updateUserStatus(currentUser, canAccess);
        adminUserAuthNotice.style.display = canAccess ? "none" : "block";
        applyPermissionUI();
        if (adminLoginMsg) {
          adminLoginMsg.textContent = canAccess
            ? "Signed in."
            : "Signed in, but admin access is restricted.";
        }
        const activeLink = document.querySelector(".nav a.is-active");
        const panelId = activeLink?.dataset.panel || navLinks[0]?.dataset.panel;
        if (panelId) showPanel(panelId);
      } catch (e) {
        console.error(e);
        if (adminLoginMsg) adminLoginMsg.textContent = "Login failed. Try again.";
      }
    }

    async function loadUserPermissions(){
      userPermissions = new Set();
      if (!currentUser) return;
      if (currentUser.is_admin) return;
      try {
        const { data: perms, error: pErr } = await supabaseClient
          .rpc("rpc_get_user_permissions", { p_token: currentToken });
        if (pErr) throw pErr;
        (perms || []).forEach(p => {
          if (p.permission_key) userPermissions.add(p.permission_key);
        });
      } catch (e) {
        console.warn("Failed to load user permissions", e);
      }
    }

    function hasPermission(key){
      if (!currentUser) return false;
      if (currentUser.is_admin) return true;
      return userPermissions.has(key);
    }

    function requirePermission(key, msg){
      if (hasPermission(key)) return true;
      alert(msg || "Permission required.");
      return false;
    }

    function updateUserStatus(user, ok){
      if (!adminUserStatus) return;
      const label = adminUserStatus.querySelector("span:last-child");
      if (!user || !ok){
        adminUserStatus.classList.remove("is-active");
        if (label) label.textContent = "Not signed in";
        // Hide View As button
        const viewAsBtn = document.getElementById("viewAsBtn");
        if (viewAsBtn) viewAsBtn.style.display = "none";
        return;
      }
      adminUserStatus.classList.add("is-active");
      const roleLabel = user.is_admin ? "superadmin" : "admin";
      if (label) label.textContent = `Signed in: ${user.name} (${roleLabel})`;
      // Show View As button only for superadmin
      const viewAsBtn = document.getElementById("viewAsBtn");
      if (viewAsBtn) viewAsBtn.style.display = user.is_admin ? "block" : "none";
    }

    let currentUserLoaded = false;
    async function ensureCurrentUser(){
      if (currentUserLoaded) return currentUser;
      const user = await loadCurrentUser();
      currentUserLoaded = !!user;
      return user;
    }

    function applyPermissionUI(){
      const canViewUsers = hasPermission("users.view");
      const canCreateUsers = hasPermission("users.create");
      const canEditUsers = hasPermission("users.edit");
      const canReorder = hasPermission("users.reorder");
      const canManagePermissions = hasPermission("system.admin_panel");

      const usersNav = document.querySelector('[data-panel="users"]');
      if (usersNav) usersNav.style.display = canViewUsers ? "flex" : "none";

      const reorderNav = document.querySelector('[data-panel="reorder"]');
      if (reorderNav) reorderNav.style.display = canReorder ? "flex" : "none";

      const permissionsNav = document.querySelector('[data-panel="permissions"]');
      if (permissionsNav) permissionsNav.style.display = canManagePermissions ? "flex" : "none";

      // Non-staff admin is admin-only
      const nsNav = document.querySelector('[data-panel="non-staff"]');
      if (nsNav) nsNav.style.display = currentUser?.is_admin ? 'flex' : 'none';

      if (adminAddUserBtn) adminAddUserBtn.disabled = !canCreateUsers;

      usersPageTabs.forEach(tab => {
        if (tab.dataset.usersPage === "add") {
          tab.style.pointerEvents = canCreateUsers ? "auto" : "none";
          tab.style.opacity = canCreateUsers ? "1" : "0.5";
          tab.title = canCreateUsers ? "" : "Restricted";
        }
        if (tab.dataset.usersPage === "edit") {
          tab.style.pointerEvents = canEditUsers ? "auto" : "none";
          tab.style.opacity = canEditUsers ? "1" : "0.5";
          tab.title = canEditUsers ? "" : "Restricted";
        }
      });

      document.querySelectorAll("input[data-perm-group]").forEach(chk => {
        chk.disabled = !canEditUsers;
      });
    }

    async function loadAdminUsers(){
      if (!adminUsersList) return;
      if (!hasPermission("users.view")) {
        adminUsersList.innerHTML = `<div class="page-subtitle" style="padding:10px;">Restricted</div>`;
        return;
      }
      adminUsersList.textContent = "Loading users...";

      let rows = null;
      try {
        const { data, error } = await supabaseClient.rpc("admin_get_users", {
          p_token: currentToken,
          p_include_inactive: true
        });
        if (error) throw error;
        rows = (data || []).slice().sort((a, b) => {
          const roleDiff = (a.role_id || 0) - (b.role_id || 0);
          if (roleDiff !== 0) return roleDiff;
          const aOrder = a.display_order ?? 9999;
          const bOrder = b.display_order ?? 9999;
          if (aOrder !== bOrder) return aOrder - bOrder;
          return (a.name || "").localeCompare(b.name || "");
        });
      } catch (err){
        console.error(err);
        adminUsersList.textContent = "Failed to load users.";
        return;
      }

      adminUsersCache = rows || [];
      window.adminUsersCache = adminUsersCache; // Expose to window for other modules
      renderAdminUsers();
    }

    function renderAdminUsers(){
      if (!adminUsersList) return;

      const q = (adminUserSearch?.value || "").trim().toLowerCase();
      const showInactive = !!adminShowInactiveUsers?.checked;
      let rows = adminUsersCache.slice();
      if (!showInactive) rows = rows.filter(u => u.is_active !== false);
      if (q) rows = rows.filter(u => (u.name || "").toLowerCase().includes(q));

      if (!rows.length){
        adminUsersList.innerHTML = `<div class="page-subtitle" style="padding:10px;">No users.</div>`;
        return;
      }

      const canEditUsers = hasPermission("users.edit");
      const canToggleUsers = hasPermission("users.toggle_active");

      const groups = [
        { title: "Charge Nurses", role_id: 1 },
        { title: "Staff Nurses", role_id: 2 },
        { title: "Nursing Assistants", role_id: 3 },
      ];

      const html = [];
      for (const g of groups){
        const members = rows.filter(u => Number(u.role_id) === g.role_id);
        if (!members.length) continue;
        html.push(`<div class="user-group-title">${g.title}</div>`);
        html.push(members.map(u => {
          const isAdminAccount = !!u.is_admin;
          const allowEdit = canEditUsers && (!isAdminAccount || currentUser?.is_admin);
          const allowToggle = canToggleUsers && (!isAdminAccount || currentUser?.is_admin);
          const actionButtons = []
            .concat(allowEdit ? `<button type="button" class="btn" data-act="edit" data-id="${u.id}">Edit</button>` : [])
            .concat(allowToggle ? `<button type="button" class="btn" data-act="toggle" data-id="${u.id}">${u.is_active === false ? "Reactivate" : "Deactivate"}</button>` : [])
            .join("");

          return `
            <div class="user-row" draggable="true" data-user-id="${u.id}" data-role-id="${g.role_id}">
              <div class="drag-handle" title="Drag to reorder">|||</div>
              <div class="user-meta">
                <div class="user-name">
                  ${escapeHtml(u.name || "")}
                  ${u.is_admin ? `<span class="user-tag admin">admin</span>` : ""}
                  ${u.is_active === false ? `<span class="user-tag inactive">inactive</span>` : ""}
                </div>
              </div>
              <div class="user-actions">
                ${actionButtons}
              </div>
            </div>
          `;
        }).join(""));
      }

      adminUsersList.innerHTML = html.join("");
      renderAdminUserSelectOptions(adminEditUserSearch?.value || "");
    }

    function renderAdminUserSelectOptions(filterText){
      if (!adminEditUserSelect) return;
      if (!hasPermission("users.edit")) {
        adminEditUserSelect.innerHTML = `<option value="">Restricted</option>`;
        return;
      }
      const q = (filterText || "").trim().toLowerCase();
      const options = adminUsersCache
        .slice()
        .filter(u => (u.name || "").toLowerCase().includes(q))
        .map(u => `<option value="${u.id}">${escapeHtml(u.name || "")}</option>`);
      adminEditUserSelect.innerHTML = `<option value="">Select user...</option>${options.join("")}`;
    }

    function renderAdminUsersReorder(){
      if (!adminUsersReorderList) return;
      if (!hasPermission("users.reorder")) {
        adminUsersReorderList.innerHTML = `<div class="page-subtitle" style="padding:10px;">Restricted</div>`;
        return;
      }
      const rows = adminUsersCache.slice().filter(u => u.is_active !== false);
      if (!rows.length){
        adminUsersReorderList.innerHTML = `<div class="page-subtitle" style="padding:10px;">No users.</div>`;
        return;
      }

      const groups = [
        { title: "Charge Nurses", role_id: 1 },
        { title: "Staff Nurses", role_id: 2 },
        { title: "Nursing Assistants", role_id: 3 },
      ];

      const html = [];
      for (const g of groups){
        const members = rows.filter(u => Number(u.role_id) === g.role_id);
        if (!members.length) continue;
        html.push(`<div class="user-group-title">${g.title}</div>`);
        html.push(members.map(u => {
          return `
            <div class="user-row" draggable="true" data-user-id="${u.id}" data-role-id="${g.role_id}">
              <div class="drag-handle" title="Drag to reorder">|||</div>
              <div class="user-meta">
                <div class="user-name">${escapeHtml(u.name || "")}</div>
              </div>
            </div>
          `;
        }).join(""));
      }

      adminUsersReorderList.innerHTML = html.join("");
    }

    function clearUserEditor(){
      adminEditingUserId = null;
      if (adminEditUserName) adminEditUserName.value = "";
      if (adminEditUserRole) adminEditUserRole.value = "2";
      if (adminEditUserPin)  adminEditUserPin.value = "";
      if (adminUserEditHelp) adminUserEditHelp.textContent = "Fill details and click Save.";
      if (adminEditUserName) adminEditUserName.disabled = false;
      if (adminEditUserRole) adminEditUserRole.disabled = false;
      if (adminEditUserPin) adminEditUserPin.disabled = false;
      if (adminPrefShiftClustering) adminPrefShiftClustering.value = 3;
      if (adminPrefNightAppetite) adminPrefNightAppetite.value = 3;
      if (adminPrefWeekendAppetite) adminPrefWeekendAppetite.value = 3;
      if (adminPrefLeaveAdjacency) adminPrefLeaveAdjacency.value = 3;
      if (adminPrefShiftClusteringValue) adminPrefShiftClusteringValue.textContent = "3";
      if (adminPrefNightAppetiteValue) adminPrefNightAppetiteValue.textContent = "3";
      if (adminPrefWeekendAppetiteValue) adminPrefWeekendAppetiteValue.textContent = "3";
      if (adminPrefLeaveAdjacencyValue) adminPrefLeaveAdjacencyValue.textContent = "3";
      if (adminCanBeInChargeDay) adminCanBeInChargeDay.checked = false;
      if (adminCanBeInChargeNight) adminCanBeInChargeNight.checked = false;
      if (adminCannotBeSecondDay) adminCannotBeSecondDay.checked = false;
      if (adminCannotBeSecondNight) adminCannotBeSecondNight.checked = false;
      if (adminCanWorkNights) adminCanWorkNights.checked = true;
      if (adminPrefsHelp) adminPrefsHelp.textContent = "";
    }

    function setAdminPref(control, labelEl, value){
      if (control) control.value = value;
      if (labelEl) labelEl.textContent = String(value);
    }

    function populateAdminPreferences(u){
      const prefShift = Number(u?.pref_shift_clustering) || 3;
      const prefNight = Number(u?.pref_night_appetite) || 3;
      const prefWeekend = Number(u?.pref_weekend_appetite) || 3;
      const prefLeave = Number(u?.pref_leave_adjacency) || 3;
      setAdminPref(adminPrefShiftClustering, adminPrefShiftClusteringValue, prefShift);
      setAdminPref(adminPrefNightAppetite, adminPrefNightAppetiteValue, prefNight);
      setAdminPref(adminPrefWeekendAppetite, adminPrefWeekendAppetiteValue, prefWeekend);
      setAdminPref(adminPrefLeaveAdjacency, adminPrefLeaveAdjacencyValue, prefLeave);
      if (adminCanBeInChargeDay) adminCanBeInChargeDay.checked = !!u?.can_be_in_charge_day;
      if (adminCanBeInChargeNight) adminCanBeInChargeNight.checked = !!u?.can_be_in_charge_night;
      if (adminCannotBeSecondDay) adminCannotBeSecondDay.checked = !!u?.cannot_be_second_rn_day;
      if (adminCannotBeSecondNight) adminCannotBeSecondNight.checked = !!u?.cannot_be_second_rn_night;
      if (adminCanWorkNights) adminCanWorkNights.checked = u?.can_work_nights !== false;
      if (adminPrefsHelp) adminPrefsHelp.textContent = "";
    }

    function readPrefValue(input){
      const v = Number(input?.value);
      return Number.isFinite(v) && v >= 1 && v <= 5 ? v : 3;
    }

    async function saveAdminPreferences(){
      if (!requirePermission("users.edit", "Permission required to edit users.")) return;
      if (!adminEditingUserId) return alert("Select a user first.");
      if (adminPrefsHelp) adminPrefsHelp.textContent = "Saving preferences...";
      const payload = {
        p_token: currentToken,
        p_target_user_id: adminEditingUserId,
        p_pref_shift_clustering: readPrefValue(adminPrefShiftClustering),
        p_pref_night_appetite: readPrefValue(adminPrefNightAppetite),
        p_pref_weekend_appetite: readPrefValue(adminPrefWeekendAppetite),
        p_pref_leave_adjacency: readPrefValue(adminPrefLeaveAdjacency),
        p_can_be_in_charge_day: !!adminCanBeInChargeDay?.checked,
        p_can_be_in_charge_night: !!adminCanBeInChargeNight?.checked,
        p_cannot_be_second_rn_day: !!adminCannotBeSecondDay?.checked,
        p_cannot_be_second_rn_night: !!adminCannotBeSecondNight?.checked,
        p_can_work_nights: !!adminCanWorkNights?.checked
      };
      try {
        const { error } = await supabaseClient.rpc("admin_update_user_preferences", payload);
        if (error) throw error;
        const idx = adminUsersCache.findIndex(u => u.id === adminEditingUserId);
        if (idx >= 0) {
          adminUsersCache[idx] = {
            ...adminUsersCache[idx],
            pref_shift_clustering: payload.p_pref_shift_clustering,
            pref_night_appetite: payload.p_pref_night_appetite,
            pref_weekend_appetite: payload.p_pref_weekend_appetite,
            pref_leave_adjacency: payload.p_pref_leave_adjacency,
            can_be_in_charge_day: payload.p_can_be_in_charge_day,
            can_be_in_charge_night: payload.p_can_be_in_charge_night,
            cannot_be_second_rn_day: payload.p_cannot_be_second_rn_day,
            cannot_be_second_rn_night: payload.p_cannot_be_second_rn_night,
            can_work_nights: payload.p_can_work_nights
          };
        }
        if (adminPrefsHelp) adminPrefsHelp.textContent = "Preferences saved.";
      } catch (e){
        console.error(e);
        if (adminPrefsHelp) adminPrefsHelp.textContent = "Save failed.";
        alert("Failed to save preferences. Check console.");
      }
    }

    function clearUserAddForm(){
      if (adminAddUserName) adminAddUserName.value = "";
      if (adminAddUserRole) adminAddUserRole.value = "2";
      if (adminAddUserPin) adminAddUserPin.value = "";
      if (adminUserAddHelp) adminUserAddHelp.textContent = "Fill details and click Create.";
      const canCreate = hasPermission("users.create");
      if (adminAddUserName) adminAddUserName.disabled = !canCreate;
      if (adminAddUserRole) adminAddUserRole.disabled = !canCreate;
      if (adminAddUserPin) adminAddUserPin.disabled = !canCreate || !hasPermission("users.set_pin");
      if (adminCreateUserBtn) adminCreateUserBtn.disabled = !canCreate;
      if (!canCreate && adminUserAddHelp) adminUserAddHelp.textContent = "Restricted.";
    }

    function openAddUserSection(){
      if (!requirePermission("users.create", "Permission required to add users.")) return;
      showUsersPage("add");
      clearUserAddForm();
    }

    async function startEditUser(userId){
      if (!requirePermission("users.edit", "Permission required to edit users.")) return;
      const u = adminUsersCache.find(x => x.id === userId);
      if (!u) return;
      adminEditingUserId = u.id;
      
      // Set user name header and role badge
      const titleEl = document.getElementById("editUserPageTitle");
      const roleBadgeEl = document.getElementById("editUserRoleBadge");
      if (titleEl) titleEl.textContent = u.name || "User";
      
      // Set role badge color and text
      const roleNames = { 1: "Charge Nurse", 2: "Staff Nurse", 3: "Nursing Assistant" };
      const roleBgColors = { 1: "#2563eb", 2: "#7c3aed", 3: "#0891b2" };
      const roleText = roleNames[u.role_id] || "Unknown Role";
      const roleBg = roleBgColors[u.role_id] || "#6b7280";
      
      if (roleBadgeEl) {
        roleBadgeEl.textContent = roleText;
        roleBadgeEl.style.background = roleBg;
      }
      
      adminEditUserName.value = u.name || "";
      adminEditUserRole.value = String(u.role_id || 2);
      adminEditUserPin.value = "";
      adminUserEditHelp.textContent = "Leave PIN blank to keep current PIN.";
      const isAdminAccount = !!u.is_admin;
      const canEditAdmin = currentUser?.is_admin;
      const canEditThisUser = !isAdminAccount || canEditAdmin;
      const canSetPin = hasPermission("users.set_pin") && canEditThisUser;
      adminEditUserName.disabled = !canEditThisUser;
      adminEditUserRole.disabled = !canEditThisUser;
      adminEditUserPin.disabled = !canSetPin;
      if (!canEditThisUser) {
        adminUserEditHelp.textContent = "Admin accounts are read-only unless you are superadmin.";
      } else if (!canSetPin) {
        adminUserEditHelp.textContent = "You can edit this user, but PIN changes are restricted.";
      }
      if (adminEditUserSelect) adminEditUserSelect.value = String(userId);
      populateAdminPreferences(u);
      await loadPatternDefinitions();
      await loadUserPattern();
      loadUserLeaveSummary(userId);
      loadUserLeaveBalance(userId);
      showUsersPage("edit");
    }

    async function loadUserLeaveSummary(userId) {
      const totalDaysEl = document.getElementById("editUserTotalLeaveDays");
      const entriesListEl = document.getElementById("editUserLeaveEntriesList");
      const manageLeaveBtn = document.getElementById("editUserManageLeaveBtn");

      if (!totalDaysEl || !entriesListEl) {
        console.warn("[ADMIN] Leave summary elements not found");
        return;
      }

      // Set loading state
      totalDaysEl.textContent = "...";
      entriesListEl.innerHTML = '<p style="text-align:center; color:#9ca3af; padding:20px 0; font-size:14px;">Loading...</p>';

      try {
        const { data, error } = await supabaseClient.rpc("admin_get_user_leave_entries", {
          p_token: currentToken,
          p_user_id: userId
        });

        if (error) throw error;

        const entries = data || [];
        let totalDays = 0;

        entries.forEach(entry => {
          totalDays += entry.leave_days || 0;
        });

        totalDaysEl.textContent = totalDays.toFixed(1);

        if (entries.length === 0) {
          entriesListEl.innerHTML = '<p style="text-align:center; color:#9ca3af; padding:20px 0; font-size:14px;">No leave entries for this user.</p>';
        } else {
          entriesListEl.innerHTML = '';
          entries.forEach(entry => {
            const startDate = new Date(entry.start_date);
            const endDate = new Date(entry.end_date);
            const dateRange = startDate.toLocaleDateString() === endDate.toLocaleDateString()
              ? startDate.toLocaleDateString("en-GB")
              : `${startDate.toLocaleDateString("en-GB")} - ${endDate.toLocaleDateString("en-GB")}`;

            const card = document.createElement("div");
            card.style.cssText = "background:white; border:1px solid #e5e7eb; border-radius:6px; padding:10px; margin-bottom:6px; font-size:14px;";
            card.innerHTML = `
              <div style="font-weight:600; color:#1f2937; margin-bottom:2px;">${dateRange}</div>
              <div style="font-size:13px; color:#6b7280;">
                ${entry.leave_days} days
              </div>
            `;
            entriesListEl.appendChild(card);
          });
        }

        // Set up "Manage Leave" button to navigate to Leave Management panel
        if (manageLeaveBtn) {
          manageLeaveBtn.onclick = () => {
            // Switch to leave-management panel
            const leavePanel = document.querySelector('[data-panel="leave-management"]');
            if (leavePanel) {
              leavePanel.click();
              // Pre-select this user
              setTimeout(() => {
                const leaveUserSelect = document.getElementById("leaveUserSelect");
                if (leaveUserSelect) {
                  leaveUserSelect.value = userId;
                  leaveUserSelect.dispatchEvent(new Event("change"));
                }
              }, 100);
            }
          };
        }

      } catch (err) {
        console.error("[ADMIN] Error loading leave summary:", err);
        totalDaysEl.textContent = "Error";
        entriesListEl.innerHTML = '<p style="text-align:center; color:#ef4444; padding:20px 0; font-size:14px;">Failed to load leave data.</p>';
      }
    }

    async function loadUserLeaveBalance(userId) {
      const balanceSection = document.getElementById("editUserLeaveBalanceSection");
      const cardsContainer = document.getElementById("editUserLeaveBalanceCards");
      const balanceYearSpan = document.getElementById("balanceYear");
      
      if (!balanceSection || !cardsContainer) {
        console.warn("[ADMIN] Leave balance elements not found");
        return;
      }

      try {
        // Get user details to check role
        const user = adminUsersCache.find(x => x.id === userId);
        if (!user) {
          console.warn("[ADMIN] User not found in cache");
          return;
        }

        const isNA = user.role_id === 3; // Nursing Assistant

        // Hide the balance section for Nursing Assistants
        if (isNA) {
          balanceSection.style.display = "none";
          return;
        }

        // Show the section for RN/SN
        balanceSection.style.display = "block";

        // Set loading state
        cardsContainer.innerHTML = '<p style="text-align:center; color:#9ca3af; padding:20px 0; font-size:13px;">Loading balance...</p>';

        // Fetch leave balance
        const { data, error } = await supabaseClient.rpc("admin_get_user_leave_balance", {
          p_token: currentToken,
          p_user_id: userId
        });

        if (error) throw error;

        if (!data || data.length === 0) {
          cardsContainer.innerHTML = '<p style="text-align:center; color:#ef4444; padding:10px 0; font-size:13px;">Could not load balance.</p>';
          return;
        }

        const balance = data[0];
        const hasAdjustments = balance.adjustments_days && balance.adjustments_days !== 0;

        // Update year display
        if (balanceYearSpan) balanceYearSpan.textContent = balance.leave_year;

        // Render balance cards
        cardsContainer.innerHTML = `
          <div style="display:grid; grid-template-columns: repeat(4, 1fr); gap:8px; margin-bottom:12px;">
            <div style="padding:10px; background:#f0fdf4; border:1px solid #86efac; border-radius:7px; text-align:center;">
              <div style="font-size:10px; color:#166534; margin-bottom:3px; font-weight:600; text-transform:uppercase; letter-spacing:0.3px;">Base</div>
              <div style="font-size:20px; font-weight:700; color:#16a34a; line-height:1;">${balance.annual_entitlement_days}</div>
            </div>
            
            <div style="padding:10px; background:${hasAdjustments ? '#fef3c7' : '#f9fafb'}; border:1px solid ${hasAdjustments ? '#fcd34d' : '#e5e7eb'}; border-radius:7px; text-align:center;">
              <div style="font-size:10px; color:${hasAdjustments ? '#92400e' : '#6b7280'}; margin-bottom:3px; font-weight:600; text-transform:uppercase; letter-spacing:0.3px;">Adjust</div>
              <div style="font-size:20px; font-weight:700; color:${hasAdjustments ? '#f59e0b' : '#6b7280'}; line-height:1;">
                ${balance.adjustments_days > 0 ? '+' : ''}${balance.adjustments_days}
              </div>
            </div>
            
            <div style="padding:10px; background:#fef2f2; border:1px solid #fca5a5; border-radius:7px; text-align:center;">
              <div style="font-size:10px; color:#991b1b; margin-bottom:3px; font-weight:600; text-transform:uppercase; letter-spacing:0.3px;">Taken</div>
              <div style="font-size:20px; font-weight:700; color:#dc2626; line-height:1;">${balance.used_days}</div>
            </div>
            
            <div style="padding:10px; background:#dbeafe; border:1px solid #60a5fa; border-radius:7px; text-align:center;">
              <div style="font-size:10px; color:#1e40af; margin-bottom:3px; font-weight:600; text-transform:uppercase; letter-spacing:0.3px;">Remaining</div>
              <div style="font-size:20px; font-weight:700; color:#2563eb; line-height:1;">${balance.remaining_days}</div>
            </div>
          </div>
        `;

        // Populate input fields
        const entitlementInput = document.getElementById("editUserLeaveEntitlementDays");
        const yearInput = document.getElementById("editUserLeaveYear");
        if (entitlementInput) entitlementInput.value = balance.annual_entitlement_days;
        if (yearInput) yearInput.value = balance.leave_year;

        // Load adjustments history
        await loadLeaveAdjustments(userId, balance.leave_year);

        // Set up save button
        const saveBtn = document.getElementById("editUserSaveLeaveEntitlementBtn");
        if (saveBtn) {
          saveBtn.onclick = async () => {
            const entitlementDays = parseFloat(entitlementInput.value);
            const leaveYear = parseInt(yearInput.value);

            if (isNaN(entitlementDays) || entitlementDays < 0) {
              alert("Please enter a valid entitlement value");
              return;
            }

            if (isNaN(leaveYear) || leaveYear < 2020) {
              alert("Please enter a valid year");
              return;
            }

            try {
              const { error } = await supabaseClient.rpc("admin_set_user_leave_entitlement", {
                p_token: currentToken,
                p_user_id: userId,
                p_entitlement_days: entitlementDays,
                p_leave_year: leaveYear
              });

              if (error) throw error;

              alert("Leave entitlement updated successfully");
              await loadUserLeaveBalance(userId);
            } catch (err) {
              console.error("[ADMIN] Error saving leave entitlement:", err);
              alert("Failed to save: " + err.message);
            }
          };
        }

        // Set up add adjustment button
        const addBtn = document.getElementById("addLeaveAdjustmentBtn");
        if (addBtn) {
          addBtn.onclick = () => {
            showAddAdjustmentDialog(userId, balance.leave_year);
          };
        }

      } catch (err) {
        console.error("[ADMIN] Error loading leave balance:", err);
        cardsContainer.innerHTML = '<p style="text-align:center; color:#ef4444; padding:10px 0; font-size:13px;">Failed to load balance.</p>';
      }
    }

    async function loadLeaveAdjustments(userId, year) {
      const listEl = document.getElementById("leaveAdjustmentsList");
      if (!listEl) return;

      try {
        const { data, error } = await supabaseClient.rpc("admin_get_leave_adjustments", {
          p_token: currentToken,
          p_user_id: userId,
          p_year: year
        });

        if (error) throw error;

        if (!data || data.length === 0) {
          listEl.innerHTML = '<p style="text-align:center; color:#9ca3af; font-size:13px; padding:10px 0;">No adjustments for this year</p>';
          return;
        }

        let html = '<div style="display:flex; flex-direction:column; gap:8px;">';
        
        data.forEach(adj => {
          const isPositive = adj.adjustment_days > 0;
          const dateStr = new Date(adj.adjustment_date).toLocaleDateString('en-GB');
          const typeLabel = adj.adjustment_type.replace('_', ' ').toUpperCase();
          
          html += `
            <div style="padding:10px; background:${isPositive ? '#f0fdf4' : '#fef2f2'}; border:1px solid ${isPositive ? '#bbf7d0' : '#fecaca'}; border-radius:6px;">
              <div style="display:flex; justify-content:space-between; align-items:start; margin-bottom:4px;">
                <div style="flex:1;">
                  <span style="display:inline-block; padding:2px 8px; background:${isPositive ? '#dcfce7' : '#fee2e2'}; color:${isPositive ? '#166534' : '#991b1b'}; border-radius:4px; font-size:11px; font-weight:600; margin-right:8px;">
                    ${typeLabel}
                  </span>
                  <span style="font-size:13px; font-weight:700; color:${isPositive ? '#16a34a' : '#dc2626'};">
                    ${isPositive ? '+' : ''}${adj.adjustment_days} days
                  </span>
                  <span style="font-size:12px; color:#6b7280; margin-left:6px;">
                    (${isPositive ? '+' : ''}${(adj.adjustment_days * 8).toFixed(1)}h)
                  </span>
                </div>
                <div style="font-size:11px; color:#6b7280;">${dateStr}</div>
              </div>
              <div style="font-size:12px; color:#374151; margin-bottom:2px;">
                <strong>Reason:</strong> ${adj.reason}
              </div>
              ${adj.notes ? `<div style="font-size:11px; color:#6b7280;">Note: ${adj.notes}</div>` : ''}
              <div style="font-size:11px; color:#9ca3af; margin-top:4px;">
                Added by ${adj.created_by_name || 'Unknown'} on ${new Date(adj.created_at).toLocaleString('en-GB')}
              </div>
            </div>
          `;
        });

        html += '</div>';
        listEl.innerHTML = html;

      } catch (err) {
        console.error("[ADMIN] Error loading adjustments:", err);
        listEl.innerHTML = '<p style="text-align:center; color:#ef4444; font-size:13px; padding:10px 0;">Failed to load adjustments</p>';
      }
    }

    function showAddAdjustmentDialog(userId, currentYear) {
      const user = adminUsersCache.find(x => x.id === userId);
      if (!user) return;

      const dialogHtml = `
        <div style="position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.5); z-index:10000; display:flex; align-items:center; justify-content:center;" id="addAdjustmentDialog">
          <div style="background:white; border-radius:8px; width:90%; max-width:500px; max-height:90vh; overflow-y:auto; box-shadow:0 10px 25px rgba(0,0,0,0.3);">
            <div style="padding:20px; border-bottom:1px solid #e5e7eb;">
              <h3 style="margin:0; font-size:18px; font-weight:600; color:#1f2937;">Add Leave Adjustment</h3>
              <p style="margin:6px 0 0 0; font-size:13px; color:#6b7280;">For: ${user.name} (Year: ${currentYear})</p>
            </div>
            
            <div style="padding:20px;">
              <div style="margin-bottom:16px;">
                <label style="display:block; font-size:13px; font-weight:600; color:#374151; margin-bottom:6px;">
                  Adjustment Type *
                </label>
                <select id="adjustmentType" style="width:100%; padding:8px 12px; border:1px solid #d1d5db; border-radius:6px; font-size:14px;">
                  <option value="carry_forward">Carry Forward (from previous year)</option>
                  <option value="anniversary">Anniversary Increase</option>
                  <option value="pro_rata">Pro Rata (mid-year change)</option>
                  <option value="manual">Manual Adjustment</option>
                  <option value="correction">Correction</option>
                </select>
              </div>

              <div style="margin-bottom:16px;">
                <label style="display:block; font-size:13px; font-weight:600; color:#374151; margin-bottom:6px;">
                  Adjustment Days * (use negative for deductions)
                </label>
                <input type="number" id="adjustmentDays" step="0.5" placeholder="e.g., 5 or -2.5" 
                  style="width:100%; padding:8px 12px; border:1px solid #d1d5db; border-radius:6px; font-size:14px;" />
                <div style="font-size:11px; color:#6b7280; margin-top:4px;">
                  Hours equivalent: <span id="adjustmentHours">0</span>h
                </div>
              </div>

              <div style="margin-bottom:16px;">
                <label style="display:block; font-size:13px; font-weight:600; color:#374151; margin-bottom:6px;">
                  Reason *
                </label>
                <input type="text" id="adjustmentReason" placeholder="e.g., 5 days carried forward from 2025" 
                  style="width:100%; padding:8px 12px; border:1px solid #d1d5db; border-radius:6px; font-size:14px;" />
              </div>

              <div style="margin-bottom:16px;">
                <label style="display:block; font-size:13px; font-weight:600; color:#374151; margin-bottom:6px;">
                  Additional Notes (optional)
                </label>
                <textarea id="adjustmentNotes" rows="3" placeholder="Any additional details..."
                  style="width:100%; padding:8px 12px; border:1px solid #d1d5db; border-radius:6px; font-size:14px; resize:vertical;"></textarea>
              </div>

              <div style="margin-bottom:16px;">
                <label style="display:block; font-size:13px; font-weight:600; color:#374151; margin-bottom:6px;">
                  Leave Year
                </label>
                <input type="number" id="adjustmentYear" value="${currentYear}" min="2020" max="2100" 
                  style="width:100%; padding:8px 12px; border:1px solid #d1d5db; border-radius:6px; font-size:14px;" />
              </div>
            </div>

            <div style="padding:16px 20px; border-top:1px solid #e5e7eb; display:flex; gap:12px; justify-content:flex-end;">
              <button id="cancelAdjustmentBtn" class="btn" type="button" style="background:#f3f4f6; color:#374151;">
                Cancel
              </button>
              <button id="saveAdjustmentBtn" class="btn" type="button">
                Save Adjustment
              </button>
            </div>
          </div>
        </div>
      `;

      document.body.insertAdjacentHTML('beforeend', dialogHtml);

      // Auto-calculate hours
      const daysInput = document.getElementById("adjustmentDays");
      const hoursSpan = document.getElementById("adjustmentHours");
      daysInput.addEventListener('input', () => {
        const days = parseFloat(daysInput.value) || 0;
        hoursSpan.textContent = (days * 8).toFixed(1);
      });

      // Cancel button
      document.getElementById("cancelAdjustmentBtn").onclick = () => {
        document.getElementById("addAdjustmentDialog").remove();
      };

      // Save button
      document.getElementById("saveAdjustmentBtn").onclick = async () => {
        const type = document.getElementById("adjustmentType").value;
        const days = parseFloat(document.getElementById("adjustmentDays").value);
        const reason = document.getElementById("adjustmentReason").value.trim();
        const notes = document.getElementById("adjustmentNotes").value.trim();
        const year = parseInt(document.getElementById("adjustmentYear").value);

        if (isNaN(days) || days === 0) {
          alert("Please enter a valid adjustment (cannot be 0)");
          return;
        }

        if (!reason) {
          alert("Please enter a reason for this adjustment");
          return;
        }

        try {
          const { data, error } = await supabaseClient.rpc("admin_add_leave_adjustment", {
            p_token: currentToken,
            p_user_id: userId,
            p_adjustment_days: days,
            p_adjustment_type: type,
            p_reason: reason,
            p_leave_year: year,
            p_notes: notes || null
          });

          if (error) throw error;

          alert("Adjustment added successfully");
          document.getElementById("addAdjustmentDialog").remove();

          // Reload balance display
          await loadUserLeaveBalance(userId);

        } catch (err) {
          console.error("[ADMIN] Error adding adjustment:", err);
          alert("Failed to add adjustment: " + err.message);
        }
      };

      // Close on background click
      document.getElementById("addAdjustmentDialog").onclick = (e) => {
        if (e.target.id === "addAdjustmentDialog") {
          document.getElementById("addAdjustmentDialog").remove();
        }
      };
    }

    async function toggleUserActive(userId){
      if (!requirePermission("users.toggle_active", "Permission required to change active status.")) return;
      const u = adminUsersCache.find(x => x.id === userId);
      if (!u) return;
      if (u.is_admin && !currentUser?.is_admin) {
        alert("Admin accounts are read-only unless you are superadmin.");
        return;
      }
      const next = (u.is_active === false) ? true : false;
      const ok = confirm(`${next ? "Reactivate" : "Deactivate"} ${u.name}?`);
      if (!ok) return;

      const { error } = await supabaseClient.rpc("admin_set_user_active", {
        p_token: currentToken,
        p_target_user_id: userId,
        p_active: next
      });
      if (error){
        console.error(error);
        alert("Update failed.");
        return;
      }
      await loadAdminUsers();
    }

    async function adminSetUserPin(userId, pin){
      const { error } = await supabaseClient.rpc("admin_set_user_pin", {
        p_token: currentToken,
        p_target_user_id: userId,
        p_new_pin: pin
      });
      if (error) throw error;
    }

    async function saveUser(){
      if (!requirePermission("users.edit", "Permission required to edit users.")) return;
      const name = adminEditUserName.value.trim();
      const role_id = Number(adminEditUserRole.value);

      if (!name) return alert("Name required.");
      if (![1,2,3].includes(role_id)) return alert("Role invalid.");
      const u = adminUsersCache.find(x => x.id === adminEditingUserId);
      if (u?.is_admin && !currentUser?.is_admin) {
        alert("Admin accounts are read-only unless you are superadmin.");
        return;
      }

      try {
        const { data: userId, error } = await supabaseClient.rpc("admin_upsert_user", {
          p_token: currentToken,
          p_user_id: adminEditingUserId,
          p_name: name,
          p_role_id: role_id
        });
        if (error) throw error;
        await loadAdminUsers();
        await startEditUser(adminEditingUserId);
      } catch (e){
        console.error(e);
        alert("Save failed. Check console.");
      }
    }

    async function saveUserPin(){
      if (!requirePermission("users.set_pin", "Permission required to set PIN.")) return;
      if (!adminEditingUserId) return alert("Select a user first.");
      const pin = (adminEditUserPin.value || "").trim();
      if (pin && pin.length !== 4) return alert("PIN must be 4 digits.");
      if (!pin) return alert("Enter a 4-digit PIN.");
      
      try {
        await adminSetUserPin(adminEditingUserId, pin);
        adminEditUserPin.value = "";
        alert("PIN updated successfully.");
      } catch (e){
        console.error(e);
        alert("PIN update failed. Check console.");
      }
    }

    async function createUser(){
      if (!requirePermission("users.create", "Permission required to add users.")) return;
      const name = adminAddUserName.value.trim();
      const role_id = Number(adminAddUserRole.value);
      const pin = (adminAddUserPin.value || "").trim();

      if (!name) return alert("Name required.");
      if (![1,2,3].includes(role_id)) return alert("Role invalid.");
      if (pin && pin.length !== 4) return alert("PIN must be 4 digits.");
      if (pin && !hasPermission("users.set_pin")) return alert("Permission required to set PIN.");

      try {
        const { data: userId, error } = await supabaseClient.rpc("admin_upsert_user", {
          p_token: currentToken,
          p_user_id: null,
          p_name: name,
          p_role_id: role_id
        });
        if (error) throw error;
        if (pin) await adminSetUserPin(userId, pin);
        await loadAdminUsers();
        clearUserAddForm();
        alert("User created.");
      } catch (e){
        console.error(e);
        alert("Create failed. Check console.");
      }
    }

    function showUsersPage(id){
      usersPages.forEach(page => {
        page.style.display = page.id === `usersPage${id[0].toUpperCase()}${id.slice(1)}` ? "block" : "none";
      });
      usersPageTabs.forEach(tab => {
        tab.classList.toggle("is-active", tab.dataset.usersPage === id);
      });
      if (id === "add") {
        clearUserAddForm();
      }
      if (id === "edit") {
        if (!hasPermission("users.edit")) {
          if (adminUserEditHelp) adminUserEditHelp.textContent = "Restricted.";
          if (adminEditUserName) adminEditUserName.disabled = true;
          if (adminEditUserRole) adminEditUserRole.disabled = true;
          if (adminEditUserPin) adminEditUserPin.disabled = true;
        }
      }
    }

    let draggedElement = null;
    let draggedRoleId = null;


    async function updateUserDisplayOrder(roleId) {
      if (!requirePermission("users.reorder", "Permission required to reorder rota.")) return;
      try {
        const rows = Array.from(adminUsersList.querySelectorAll(`.user-row[data-role-id="${roleId}"]`));
        for (let i = 0; i < rows.length; i++) {
          const userId = rows[i].dataset.userId;
          const { error } = await supabaseClient.rpc("admin_reorder_users", {
            p_token: currentToken,
            p_user_id: userId,
            p_display_order: i + 1
          });
          if (error) throw error;
        }
        await loadAdminUsers();
      } catch (error) {
        console.error('Error updating user order:', error);
        alert(`Failed to save new order: ${error.message}`);
      }
    }

    function showPanel(id){
      panels.forEach(panel => {
        panel.style.display = panel.id === id ? "block" : "none";
      });
      navLinks.forEach(link => {
        link.classList.toggle("is-active", link.dataset.panel === id);
      });
      if (id === "users" && !usersLoaded){
        usersLoaded = true;
        ensureCurrentUser().then((u) => {
          if (u && hasPermission("users.view")) {
            loadPermissionGroups();
            loadAdminUsers();
            clearUserEditor();
            clearUserAddForm();
            showUsersPage("view");
          }
        });
      }
      if (id === "reorder"){
        ensureCurrentUser().then((u) => {
          if (u && hasPermission("users.reorder")) {
            loadAdminUsers().then(renderAdminUsersReorder);
          }
        });
      }
      if (id === "permissions"){
        ensureCurrentUser().then(() => loadPermissionsCatalogue());
      }
      if (id === "patterns"){
        ensureCurrentUser().then(() => loadPatterns());
      }
      if (id === "shift-catalogue"){
        ensureCurrentUser().then(() => loadShiftsCatalogue());
      }
      if (id === "notices"){
        ensureCurrentUser().then(() => {
          if (hasPermission("notices.view_admin")) {
            loadAdminNotices();
          }
        });
      }
      if (id === "shift-swaps"){
        ensureCurrentUser().then(() => {
          if (hasPermission("rota.swap")) {
            loadAdminSwapsPending();
            loadAdminSwapsExecuted();
          }
        });
      }
      if (id === 'non-staff'){
        ensureCurrentUser().then(() => {
          if (!currentUser?.is_admin) {
            if (nsList) nsList.innerHTML = `<div class="page-subtitle" style="padding:10px;">Restricted</div>`;
            return;
          }
          loadNonStaffList();
          clearNonStaffAddForm();
          clearNonStaffEditForm();
          showNonStaffPage('view');
        });
      }
      if (id === 'bank-holidays'){
        ensureCurrentUser().then(() => {
          loadBankHolidays();
        });
      }
    }

    navLinks.forEach(link => {
      link.addEventListener("click", (e) => {
        e.preventDefault();
        showPanel(link.dataset.panel);
      });
    });

    usersPageTabs.forEach(tab => {
      tab.addEventListener("click", () => {
        showUsersPage(tab.dataset.usersPage);
      });
    });

    shiftsPageTabs.forEach(tab => {
      tab.addEventListener("click", () => {
        const pageId = "shiftsPage" + tab.dataset.shiftsPage.split("-").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join("");
        shiftsPages.forEach(page => {
          page.style.display = page.id === pageId ? "block" : "none";
        });
        shiftsPageTabs.forEach(t => {
          t.classList.toggle("is-active", t === tab);
        });
      });
    });

    // ===== Non-staff management =====
    function showNonStaffPage(id){
      nsPages.forEach(page => {
        if (!page) return;
        const pageId = page.id.replace('nsPage','').toLowerCase();
        page.style.display = (pageId === id) ? 'block' : 'none';
      });
      nsPageTabs.forEach(tab => tab.classList.toggle('is-active', tab.dataset.nsPage === id));
    }

    function clearNonStaffAddForm(){
      if (nsAddName) nsAddName.value = '';
      if (nsAddCategory) nsAddCategory.value = 'student';
      if (nsAddRole) nsAddRole.value = 'staff_nurse';
      if (nsAddNotes) nsAddNotes.value = '';
      if (nsAddHelp) nsAddHelp.textContent = 'Fill details and click Create.';
    }

    function clearNonStaffEditForm(){
      nsEditingId = null;
      if (nsEditName) nsEditName.value = '';
      if (nsEditCategory) nsEditCategory.value = 'student';
      if (nsEditRole) nsEditRole.value = 'staff_nurse';
      if (nsEditNotes) nsEditNotes.value = '';
      if (nsEditHelp) nsEditHelp.textContent = 'Select a profile to edit.';
      if (nsToggleActiveBtn) nsToggleActiveBtn.dataset.active = 'true', nsToggleActiveBtn.textContent = 'Deactivate';
      if (nsEditSelect) nsEditSelect.value = '';
    }

    async function loadNonStaffList(){
      if (!nsList) return;
      nsList.textContent = 'Loading profiles...';
      try {
        const { data, error } = await supabaseClient.rpc('rpc_admin_list_non_staff_people', {
          p_token: currentToken,
          p_include_inactive: !!nsShowInactive?.checked,
          p_category: (nsFilterCategory?.value || '') || null,
          p_role_group: (nsFilterRole?.value || '') || null,
          p_query: (nsSearchInput?.value || '') || null
        });
        if (error) throw error;
        nsCache = data || [];
        renderNonStaffList();
        renderNonStaffSelectOptions(nsEditSearch?.value || '');
      } catch (e) {
        console.error(e);
        nsList.textContent = 'Failed to load profiles.';
      }
    }

    function renderNonStaffList(){
      if (!nsList) return;
      const q = (nsSearchInput?.value || '').trim().toLowerCase();
      const cat = nsFilterCategory?.value || '';
      const role = nsFilterRole?.value || '';
      const showInactive = !!nsShowInactive?.checked;
      let rows = nsCache.slice();
      if (!showInactive) rows = rows.filter(r => r.is_active !== false);
      if (cat) rows = rows.filter(r => r.category === cat);
      if (role) rows = rows.filter(r => r.role_group === role);
      if (q) rows = rows.filter(r => (r.name || '').toLowerCase().includes(q));
      if (!rows.length){
        nsList.innerHTML = `<div class="page-subtitle" style="padding:10px;">No profiles.</div>`;
        return;
      }
      nsList.innerHTML = rows.map(r => {
        const catTag = `<span class="user-tag">${escapeHtml(r.category)}</span>`;
        const roleTag = r.role_group ? `<span class="user-tag">${escapeHtml(r.role_group.replace('_',' '))}</span>` : '';
        const inactiveTag = r.is_active === false ? `<span class="user-tag inactive">inactive</span>` : '';
        const toggleLabel = r.is_active === false ? 'Reactivate' : 'Deactivate';
        return `
          <div class="user-row" data-ns-id="${r.id}">
            <div class="user-meta">
              <div class="user-name">${escapeHtml(r.name || '')} ${catTag} ${roleTag} ${inactiveTag}</div>
            </div>
            <div class="user-actions">
              <button type="button" class="btn" data-act="ns-edit" data-id="${r.id}">Edit</button>
              <button type="button" class="btn" data-act="ns-toggle" data-id="${r.id}">${toggleLabel}</button>
            </div>
          </div>`;
      }).join('');

      // Bind row action clicks
      nsList.querySelectorAll('button[data-act="ns-edit"]').forEach(btn => {
        btn.addEventListener('click', () => startEditNonStaff(btn.dataset.id));
      });
      nsList.querySelectorAll('button[data-act="ns-toggle"]').forEach(btn => {
        btn.addEventListener('click', () => toggleNonStaffActive(btn.dataset.id));
      });
    }

    function renderNonStaffSelectOptions(filterText){
      if (!nsEditSelect) return;
      const q = (filterText || '').trim().toLowerCase();
      const options = nsCache
        .slice()
        .filter(r => (r.name || '').toLowerCase().includes(q))
        .map(r => `<option value="${r.id}">${escapeHtml(r.name)}${r.is_active===false?' (inactive)':''}</option>`)
        .join('');
      nsEditSelect.innerHTML = `<option value="">Select profile...</option>${options}`;
    }

    function startEditNonStaff(id){
      if (!currentUser?.is_admin) { alert('Restricted'); return; }
      const r = nsCache.find(x => x.id === id);
      if (!r) return;
      nsEditingId = r.id;
      if (nsEditName) nsEditName.value = r.name || '';
      if (nsEditCategory) nsEditCategory.value = r.category || 'student';
      if (nsEditRole) nsEditRole.value = r.role_group || 'staff_nurse';
      if (nsEditNotes) nsEditNotes.value = r.notes || '';
      if (nsToggleActiveBtn){
        nsToggleActiveBtn.dataset.active = String(r.is_active !== false);
        nsToggleActiveBtn.textContent = (r.is_active === false) ? 'Reactivate' : 'Deactivate';
      }
      if (nsEditSelect) nsEditSelect.value = String(id);
      showNonStaffPage('edit');
    }

    async function saveNonStaff(){
      if (!currentUser?.is_admin) { alert('Restricted'); return; }
      if (!nsEditingId) { alert('Select a profile.'); return; }
      const name = (nsEditName?.value || '').trim();
      const category = nsEditCategory?.value || 'student';
      const role = category === 'student' ? null : (nsEditRole?.value || 'staff_nurse');
      const notes = nsEditNotes?.value || null;
      if (!name) { alert('Name required.'); return; }
      try {
        const { data, error } = await supabaseClient.rpc('rpc_update_non_staff_person', {
          p_token: currentToken,
          p_id: nsEditingId,
          p_name: name,
          p_category: category,
          p_role_group: role,
          p_notes: notes
        });
        if (error || !data?.success) throw error || new Error(data?.error || 'Update failed');
        nsEditHelp.textContent = 'Saved.';
        await loadNonStaffList();
      } catch (e) {
        console.error(e);
        alert('Save failed.');
      }
    }

    async function toggleNonStaffActive(id){
      if (!currentUser?.is_admin) { alert('Restricted'); return; }
      const r = nsCache.find(x => x.id === id);
      if (!r) return;
      const next = r.is_active === false;
      const ok = confirm(`${next ? 'Reactivate' : 'Deactivate'} ${r.name}?`);
      if (!ok) return;
      try {
        const { data, error } = await supabaseClient.rpc('rpc_set_non_staff_active', {
          p_token: currentToken,
          p_id: id,
          p_active: next
        });
        if (error || !data?.success) throw error || new Error(data?.error || 'Update failed');
        await loadNonStaffList();
        if (nsEditingId === id) startEditNonStaff(id);
      } catch (e) {
        console.error(e);
        alert('Update failed.');
      }
    }

    async function createNonStaff(){
      if (!currentUser?.is_admin) { alert('Restricted'); return; }
      const name = (nsAddName?.value || '').trim();
      const category = nsAddCategory?.value || 'student';
      const role = category === 'student' ? null : (nsAddRole?.value || 'staff_nurse');
      const notes = nsAddNotes?.value || null;
      if (!name) { alert('Name required.'); return; }
      try {
        const { data, error } = await supabaseClient.rpc('rpc_add_non_staff_person', {
          p_token: currentToken,
          p_name: name,
          p_category: category,
          p_role_group: role,
          p_notes: notes
        });
        if (error || !data?.success) throw error || new Error(data?.error || 'Create failed');
        nsAddHelp.textContent = 'Created.';
        clearNonStaffAddForm();
        await loadNonStaffList();
        showNonStaffPage('view');
      } catch (e) {
        console.error(e);
        alert('Create failed.');
      }
    }

    // Wire up NS events if elements present
    if (nsPageTabs.length){
      nsPageTabs.forEach(tab => tab.addEventListener('click', () => showNonStaffPage(tab.dataset.nsPage)));
    }
    if (nsRefreshBtn) nsRefreshBtn.addEventListener('click', loadNonStaffList);
    if (nsShowInactive) nsShowInactive.addEventListener('change', loadNonStaffList);
    if (nsFilterCategory) nsFilterCategory.addEventListener('change', loadNonStaffList);
    if (nsFilterRole) nsFilterRole.addEventListener('change', loadNonStaffList);
    if (nsSearchInput) nsSearchInput.addEventListener('input', () => { renderNonStaffList(); });
    if (nsCreateBtn) nsCreateBtn.addEventListener('click', createNonStaff);
    if (nsAddClearBtn) nsAddClearBtn.addEventListener('click', clearNonStaffAddForm);
    if (nsEditSearch) nsEditSearch.addEventListener('input', () => renderNonStaffSelectOptions(nsEditSearch.value));
    if (nsEditSelect) nsEditSelect.addEventListener('change', () => { if (nsEditSelect.value) startEditNonStaff(nsEditSelect.value); });
    if (nsSaveBtn) nsSaveBtn.addEventListener('click', saveNonStaff);
    if (nsEditCancelBtn) nsEditCancelBtn.addEventListener('click', clearNonStaffEditForm);
    if (nsToggleActiveBtn) nsToggleActiveBtn.addEventListener('click', () => {
      if (!nsEditingId) { alert('Select a profile first.'); return; }
      const r = nsCache.find(x => x.id === nsEditingId);
      if (!r) return;
      toggleNonStaffActive(nsEditingId);
    });

    // Category → role-group UI toggles
    function updateNsAddRoleVisibility(){
      if (!nsAddCategory) return;
      const wrap = document.getElementById('nsAddRoleWrap');
      if (nsAddCategory.value === 'student'){
        if (wrap) wrap.style.display = 'none';
      } else {
        if (wrap) wrap.style.display = '';
      }
    }
    function updateNsEditRoleVisibility(){
      if (!nsEditCategory) return;
      const wrap = document.getElementById('nsEditRoleWrap');
      if (nsEditCategory.value === 'student'){
        if (wrap) wrap.style.display = 'none';
      } else {
        if (wrap) wrap.style.display = '';
      }
    }
    if (nsAddCategory) { nsAddCategory.addEventListener('change', updateNsAddRoleVisibility); updateNsAddRoleVisibility(); }
    if (nsEditCategory) { nsEditCategory.addEventListener('change', updateNsEditRoleVisibility); updateNsEditRoleVisibility(); }

    let permissionsCatalogue = null;
    let permissionGroups = [];
    let groupPermissions = new Set();
    const embeddedPermissionsCatalogue = {
      groups: ["Admin", "Mentor", "Staff", "Audit Viewer"],
      categories: [
        {
          id: "user_management",
          title: "User management",
          items: [
            { key: "users.view", label: "View users", desc: "View user list, roles, and status." },
            { key: "users.create", label: "Add users", desc: "Create new user records." },
            { key: "users.edit", label: "Edit users", desc: "Edit name and role." },
            { key: "users.set_pin", label: "Change PIN", desc: "Set or reset user PINs." },
            { key: "users.toggle_active", label: "Activate/deactivate users", desc: "Change active status." },
            { key: "users.reorder", label: "Reorder rota", desc: "Change display order." }
          ]
        },
        {
          id: "requests",
          title: "Requests",
          items: [
            { key: "requests.view_all", label: "View all requests", desc: "See requests for all users." },
            { key: "requests.edit_all", label: "Edit all requests", desc: "Edit other users' requests." },
            { key: "requests.lock_cells", label: "Lock/unlock requests", desc: "Lock or unlock request cells." },
            { key: "requests.view_comments", label: "View all comments", desc: "View all week comments." }
          ]
        },
        {
          id: "rota",
          title: "Rota / Draft",
          items: [
            { key: "rota.view_draft", label: "View draft", desc: "View draft rota." },
            { key: "rota.edit_draft", label: "Edit draft", desc: "Edit draft rota cells." },
            { key: "rota.publish", label: "Publish period", desc: "Publish a period." },
            { key: "rota.approve", label: "Annotate approval", desc: "Add CNM approval annotation." }
          ]
        },
        {
          id: "periods",
          title: "Rota periods & weeks",
          items: [
            { key: "periods.create", label: "Create period", desc: "Create a new 5-week period." },
            { key: "periods.set_active", label: "Set active period", desc: "Set active period." },
            { key: "periods.toggle_hidden", label: "Hide/unhide period", desc: "Toggle hidden periods." },
            { key: "periods.set_close_time", label: "Set close time", desc: "Set or clear closes_at." },
            { key: "weeks.set_open_flags", label: "Open/close weeks", desc: "Update week open flags." }
          ]
        },
        {
          id: "notices",
          title: "Notices",
          items: [
            { key: "notices.view_admin", label: "View notices (admin)", desc: "View admin notice list." },
            { key: "notices.create", label: "Create notices", desc: "Create notices." },
            { key: "notices.edit", label: "Edit notices", desc: "Edit notices." },
            { key: "notices.toggle_active", label: "Hide/unhide notices", desc: "Toggle notice visibility." },
            { key: "notices.delete", label: "Delete notices", desc: "Delete notices." },
            { key: "notices.view_ack_counts", label: "View ack counts", desc: "View acknowledgement counts." },
            { key: "notices.view_ack_lists", label: "View ack lists", desc: "View acknowledgement lists." }
          ]
        },
        {
          id: "print_export",
          title: "Print & export",
          items: [
            { key: "print.open_admin", label: "Open admin print", desc: "Open admin print config." },
            { key: "print.export_csv", label: "Export CSV", desc: "Export CSV data." }
          ]
        },
        {
          id: "system",
          title: "System",
          items: [
            { key: "system.admin_panel", label: "Admin panel access", desc: "Access admin console." }
          ]
        }
      ]
    };

    async function loadPermissionsCatalogue(){
      if (!permissionsMatrix || !permissionGroupSelect) return;
      if (!hasPermission("system.admin_panel")) {
        permissionsMatrix.innerHTML = `<div class="page-subtitle">Restricted</div>`;
        if (permissionGroupSelect) permissionGroupSelect.disabled = true;
        if (permissionGroupName) permissionGroupName.disabled = true;
        if (createPermissionGroupBtn) createPermissionGroupBtn.disabled = true;
        if (permissionGroupHelp) permissionGroupHelp.textContent = "Restricted.";
        return;
      }
      try {
        // Load permissions from database
        const { data: permissions, error } = await supabaseClient.rpc("admin_get_permissions", {
          p_token: currentToken
        });
        
        if (error) throw error;
        
        // Group permissions by category
        const categoryMap = new Map();
        (permissions || []).forEach(perm => {
          const cat = perm.category || "other";
          if (!categoryMap.has(cat)) {
            categoryMap.set(cat, []);
          }
          categoryMap.get(cat).push({
            key: perm.key,
            label: perm.label,
            desc: perm.description || ""
          });
        });
        
        // Convert to catalogue format
        const categories = [];
        categoryMap.forEach((items, catId) => {
          categories.push({
            id: catId,
            title: catId.replace(/_/g, " ").replace(/\b\w/g, l => l.toUpperCase()),
            items: items
          });
        });
        
        // Load permission groups
        const { data: groups, error: groupsError } = await supabaseClient.rpc("admin_get_permission_groups", {
          p_token: currentToken
        });
        
        if (groupsError) throw groupsError;
        
        permissionsCatalogue = {
          groups: (groups || []).map(g => g.name),
          categories: categories
        };
        
        await loadPermissionGroups();
        renderPermissionsMatrix();
        const canEdit = hasPermission("users.edit");
        if (permissionGroupSelect) permissionGroupSelect.disabled = !canEdit;
        if (permissionGroupName) permissionGroupName.disabled = !canEdit;
        if (createPermissionGroupBtn) createPermissionGroupBtn.disabled = !canEdit;
        if (permissionGroupHelp) {
          permissionGroupHelp.textContent = canEdit
            ? "Admin group assignments are managed here. Admin group permissions are read-only to maintain system integrity."
            : "Read-only. You don't have permission to edit groups.";
        }
      } catch (e) {
        console.error("[PERMISSIONS] Error loading catalogue:", e);
        permissionsMatrix.innerHTML = `<div class="page-subtitle">Failed to load permissions catalogue: ${e.message || e}</div>`;
      }
    }

    // === PATTERNS MANAGEMENT ===
    
    async function loadPatterns(){
      try {
        const { data: patterns, error } = await supabaseClient.rpc("rpc_get_pattern_definitions", {
          p_token: currentToken
        });
        if (error) throw error;
        
        const list = document.getElementById("patternsList");
        if (!list) return;
        
        if (!patterns || patterns.length === 0){
          list.innerHTML = `<tr style="border-top:1px solid var(--line);"><td colspan="6" style="padding:12px 16px; color:var(--muted); text-align:center;">No patterns found.</td></tr>`;
          return;
        }
        
        list.innerHTML = patterns.map(p => {
          const weeklyTargets = Array.isArray(p.weekly_targets) ? p.weekly_targets.join(" / ") : p.weekly_targets;
          return `
            <tr style="border-top:1px solid var(--line);">
              <td style="padding:12px 16px;">${escapeHtml(p.name || "")}</td>
              <td style="padding:12px 16px;">${escapeHtml(p.pattern_type || "")}</td>
              <td style="padding:12px 16px;">${p.cycle_weeks || "-"}</td>
              <td style="padding:12px 16px;">${escapeHtml(weeklyTargets || "-")}</td>
              <td style="padding:12px 16px;">${p.requires_anchor ? "Yes" : "No"}</td>
              <td style="padding:12px 16px; font-size:12px; color:var(--muted);">${escapeHtml(p.notes || "")}</td>
            </tr>
          `;
        }).join("");
      } catch (e){
        console.error(e);
        const list = document.getElementById("patternsList");
        if (list) list.innerHTML = `<tr style="border-top:1px solid var(--line);"><td colspan="6" style="padding:12px 16px; color:var(--muted); text-align:center;">Failed to load patterns.</td></tr>`;
      }
    }

    async function loadPatternDefinitions(){
      try {
        const { data: patterns, error } = await supabaseClient.rpc("rpc_get_pattern_definitions", {
          p_token: currentToken
        });
        if (error) throw error;
        const sorted = (patterns || []).slice().sort((a, b) => (a.name || "").localeCompare(b.name || ""));
        
        console.log("[PATTERNS] Loaded pattern definitions:", sorted);
        
        const select = document.getElementById("adminUserPattern");
        if (!select) {
          console.error("[PATTERNS] Pattern selector not found!");
          return;
        }
        
        select.innerHTML = `<option value="">No fixed pattern</option>`;
        if (sorted && sorted.length > 0){
          sorted.forEach(p => {
            const opt = document.createElement("option");
            opt.value = String(p.id);
            opt.textContent = p.name || "Unknown";
            opt.dataset.requiresAnchor = p.requires_anchor ? "true" : "false";
            select.appendChild(opt);
          });
          console.log("[PATTERNS] Populated dropdown with", patterns.length, "patterns");
        }
      } catch (e){
        console.error("[PATTERNS] Failed to load pattern definitions:", e);
      }
    }

    async function saveUserPattern(){
      if (!requirePermission("users.edit", "Permission required.")) return;
      
      const userId = adminEditingUserId;
      if (!userId) {
        console.error("[PATTERNS] No user selected.");
        return alert("Select a user first.");
      }
      
      const patternSelect = document.getElementById("adminUserPattern");
      const anchorDateInput = document.getElementById("adminUserAnchorDate");
      
      if (!patternSelect || !anchorDateInput) {
        console.error("[PATTERNS] Form elements not found.");
        return;
      }
      
      const patternId = patternSelect.value || null;
      const anchorDate = anchorDateInput.value || null;
      
      console.log("[PATTERNS] Saving pattern for user", userId, "pattern:", patternId, "anchor:", anchorDate);
      
      try {
        if (patternId){
          // Get pattern to check if anchor is required
          const { data: patterns, error: patternErr } = await supabaseClient.rpc("rpc_get_pattern_definitions", {
            p_token: currentToken
          });
          if (patternErr) throw patternErr;
          const pattern = (patterns || []).find(p => String(p.id) === String(patternId));
          if (!pattern) throw new Error("Pattern not found.");
          
          console.log("[PATTERNS] Pattern found:", pattern);
          
          // Upsert user pattern
          const { error: upsertErr } = await supabaseClient.rpc("admin_upsert_user_pattern", {
            p_token: currentToken,
            p_user_id: userId,
            p_pattern_id: patternId,
            p_anchor_week_start_date: pattern.requires_anchor ? anchorDate : null
          });
          if (upsertErr) throw upsertErr;
          console.log("[PATTERNS] Pattern saved successfully");
        } else {
          // Delete user pattern if no pattern selected
          const { error: deleteErr } = await supabaseClient.rpc("admin_delete_user_pattern", {
            p_token: currentToken,
            p_user_id: userId
          });
          if (deleteErr) throw deleteErr;
          console.log("[PATTERNS] Pattern cleared.");
        }
      } catch (e){
        console.error("[PATTERNS] Save failed:", e);
        alert("Pattern save failed. Check console.");
      }
    }

    async function loadUserPattern(){
      const userId = adminEditingUserId;
      if (!userId) return;
      
      const patternSelect = document.getElementById("adminUserPattern");
      const anchorDateInput = document.getElementById("adminUserAnchorDate");
      
      if (!patternSelect || !anchorDateInput) return;
      
      try {
        const { data: patterns, error } = await supabaseClient.rpc("rpc_get_user_patterns", {
          p_token: currentToken
        });
        
        if (error){
          throw error;
        }
        const userPattern = (patterns || []).find(p => String(p.user_id) === String(userId));
        if (userPattern){
          patternSelect.value = String(userPattern.pattern_id || "");
          anchorDateInput.value = userPattern.anchor_week_start_date || "";
          updateAnchorDateVisibility();
        } else {
          patternSelect.value = "";
          anchorDateInput.value = "";
          updateAnchorDateVisibility();
        }
      } catch (e){
        console.error(e);
      }
    }

    function updateAnchorDateVisibility(){
      const patternSelect = document.getElementById("adminUserPattern");
      const anchorDateInput = document.getElementById("adminUserAnchorDate");
      
      if (!patternSelect || !anchorDateInput) return;
      
      const selectedOption = patternSelect.options[patternSelect.selectedIndex];
      const requiresAnchor = selectedOption?.dataset?.requiresAnchor === "true";
      
      anchorDateInput.style.display = requiresAnchor ? "block" : "none";
      if (!requiresAnchor) anchorDateInput.value = "";
    }

    async function loadPermissionGroups(){
      try {
        const { data, error } = await supabaseClient.rpc("admin_get_permission_groups", {
          p_token: currentToken
        });
        if (error) throw error;
        permissionGroups = data || [];
      } catch (e) {
        console.warn("Permissions groups table missing or unavailable.", e);
        permissionGroups = (permissionsCatalogue?.groups || []).map((name) => ({
          id: name,
          name,
          is_system: true,
          is_protected: name === "Admin"
        }));
      }

      permissionGroupSelect.innerHTML =
        `<option value="">Select group...</option>` +
        permissionGroups.map(g => `<option value="${escapeHtml(g.id)}">${escapeHtml(g.name)}</option>`).join("");

      renderUserPermissionGroups();
    }

    function renderUserPermissionGroups(){
      if (!adminUserPermissionGroups) return;
      if (!permissionGroups.length){
        adminUserPermissionGroups.innerHTML = `<div class="page-subtitle">No groups loaded.</div>`;
        return;
      }
      const canEditUsers = hasPermission("users.edit");
      adminUserPermissionGroups.innerHTML = permissionGroups.map(g => `
        <label class="perm-group-item">
          <input type="checkbox" data-perm-group="${escapeHtml(g.name)}" ${canEditUsers ? "" : "disabled"} />
          <span>${escapeHtml(g.name)}</span>
        </label>
      `).join("");
    }

    async function loadGroupPermissions(groupId){
      groupPermissions = new Set();
      if (!groupId) return;
      try {
        const { data, error } = await supabaseClient.rpc("admin_get_permission_group_permissions", {
          p_token: currentToken,
          p_group_id: groupId
        });
        if (error) throw error;
        (data || []).forEach(r => groupPermissions.add(r.permission_key));
      } catch (e) {
        console.warn("permission_group_permissions not available.", e);
      }
    }

    function isSuperAdmin(){
      return !!currentUser?.is_admin;
    }

    function isEditingAdminGroup(){
      const groupId = permissionGroupSelect?.value || "";
      const group = permissionGroups.find(g => String(g.id) === String(groupId));
      return group?.name === "Admin";
    }

    function renderPermissionsMatrix(){
      const categories = Array.isArray(permissionsCatalogue?.categories) ? permissionsCatalogue.categories : [];
      const canEdit = hasPermission("users.edit");
      const disabled = (isEditingAdminGroup() && !isSuperAdmin()) || !canEdit;

      permissionsMatrix.innerHTML = categories.map(cat => {
        const items = cat.items || [];
        const selectedCount = items.filter(item => groupPermissions.has(item.key)).length;
        const rows = items.map(item => {
          const checked = groupPermissions.has(item.key);
          return `
            <div class="permissions-row">
              <div>
                <div class="perm-label">${escapeHtml(item.label || "")}</div>
                <div class="perm-desc">${escapeHtml(item.desc || "")}</div>
                <div class="perm-key">${escapeHtml(item.key || "")}</div>
              </div>
              <div>
                <input type="checkbox" data-perm-key="${escapeHtml(item.key)}" ${checked ? "checked" : ""} ${disabled ? "disabled" : ""} />
              </div>
            </div>
          `;
        }).join("");

        return `
          <details class="perm-accordion" open>
            <summary>
              <div class="permissions-title">
                ${escapeHtml(cat.title || "")}
                <span class="perm-meta">${selectedCount}/${items.length} enabled</span>
              </div>
              <span class="perm-chevron">v</span>
            </summary>
            <div class="perm-body">
              ${rows}
            </div>
          </details>
        `;
      }).join("");
    }

    async function saveGroupPermissions(groupId){
      if (!requirePermission("users.edit", "Permission required to edit permissions.")) return;
      if (!groupId) return;
      const checkboxes = Array.from(permissionsMatrix.querySelectorAll("input[data-perm-key]"));
      const keys = checkboxes.filter(c => c.checked).map(c => c.dataset.permKey);
      try {
        const { error } = await supabaseClient.rpc("admin_set_permission_group_permissions", {
          p_token: currentToken,
          p_group_id: groupId,
          p_permission_keys: keys
        });
        if (error) throw error;
      } catch (e) {
        console.error(e);
        alert("Failed to save permissions. Check console.");
      }
    }

    async function createPermissionGroup(){
      if (!requirePermission("users.edit", "Permission required to create groups.")) return;
      const name = (permissionGroupName?.value || "").trim();
      if (!name) return alert("Group name required.");
      try {
        const { data, error } = await supabaseClient.rpc("admin_create_permission_group", {
          p_token: currentToken,
          p_name: name
        });
        if (error) throw error;
        permissionGroupName.value = "";
        await loadPermissionGroups();
        permissionGroupSelect.value = String(data);
        groupPermissions = new Set();
        renderPermissionsMatrix();
      } catch (e) {
        console.error(e);
        alert("Failed to create group. Check console.");
      }
    }

    permissionGroupSelect?.addEventListener("change", async () => {
      const groupId = permissionGroupSelect.value;
      await loadGroupPermissions(groupId);
      renderPermissionsMatrix();
      if (permissionGroupHelp) {
        permissionGroupHelp.textContent = isEditingAdminGroup() && !isSuperAdmin()
          ? "Admin group permissions are read-only to maintain system integrity. Only full system administrators can modify these."
          : "Changes are saved immediately.";
      }
    });

    permissionsMatrix?.addEventListener("change", async (e) => {
      const cb = e.target.closest("input[data-perm-key]");
      if (!cb) return;
      const groupId = permissionGroupSelect.value;
      if (!groupId) return alert("Select a group first.");
      if (isEditingAdminGroup() && !isSuperAdmin()){
        cb.checked = !cb.checked;
        return;
      }
      await saveGroupPermissions(groupId);
      await loadGroupPermissions(groupId);
      renderPermissionsMatrix();
    });

    createPermissionGroupBtn?.addEventListener("click", createPermissionGroup);

    async function loadUserPermissionGroups(userId){
      const checks = Array.from(document.querySelectorAll("input[data-perm-group]"));
      checks.forEach(c => { c.checked = false; c.disabled = true; });
      if (!hasPermission("users.edit")) {
        const help = document.querySelector("#usersPageEdit .page-subtitle");
        if (help) help.textContent = "Restricted.";
        return;
      }
      if (!userId) return;
      const u = adminUsersCache.find(x => String(x.id) === String(userId));
      if (u?.is_admin && !currentUser?.is_admin) {
        const help = document.querySelector("#usersPageEdit .page-subtitle");
        if (help) help.textContent = "Admin accounts are read-only unless you are superadmin.";
        return;
      }
      try {
        const { data, error } = await supabaseClient.rpc("admin_get_user_permission_groups", {
          p_token: currentToken,
          p_user_id: userId
        });
        if (error) throw error;
        const ids = new Set((data || []).map(r => String(r.group_id)));
        const names = new Set(permissionGroups.filter(g => ids.has(String(g.id))).map(g => g.name));
        checks.forEach(c => {
          c.checked = names.has(c.dataset.permGroup);
          c.disabled = false;
        });
      } catch (e) {
        console.warn("user_permission_groups not available.", e);
      }
    }

    async function saveUserPermissionGroups(userId){
      if (!hasPermission("users.edit")) return;
      if (!userId) return;
      const u = adminUsersCache.find(x => String(x.id) === String(userId));
      if (u?.is_admin && !currentUser?.is_admin) {
        alert("Admin accounts are read-only unless you are superadmin.");
        return;
      }
      const checks = Array.from(document.querySelectorAll("input[data-perm-group]"));
      const selectedNames = checks.filter(c => c.checked).map(c => c.dataset.permGroup);
      const groupIds = permissionGroups
        .filter(g => selectedNames.includes(g.name))
        .map(g => g.id);

      try {
        const { error } = await supabaseClient.rpc("admin_set_user_permission_groups", {
          p_token: currentToken,
          p_user_id: userId,
          p_group_ids: groupIds
        });
        if (error) throw error;
      } catch (e) {
        console.error(e);
        alert("Failed to save user groups. Check console.");
      }
    }

    async function loadShiftsCatalogue(){
      if (!hasPermission("manage_shifts")) {
        const list = document.getElementById("shiftsList");
        if (list) list.innerHTML = `<div style="padding:20px; text-align:center; color:var(--muted);">Restricted access.</div>`;
        return;
      }
      try {
        let styleFieldsAvailable = true;
        let shifts;
        const { data, error } = await supabaseClient.rpc("admin_get_shifts", {
          p_token: currentToken
        });
        if (error) throw error;
        shifts = data;

        allShifts = shifts || [];

        const list = document.getElementById("shiftsList");
        if (!list) return;
        
        list.innerHTML = (shifts || []).map(shift => {
          const hours = shift.start_time && shift.end_time ? `${shift.start_time.substring(0,5)}–${shift.end_time.substring(0,5)}` : "(no hours)";
          const staffGroups = shift.allowed_staff_groups || "None";
          const scopes = [];
          if (shift.allow_requests) scopes.push("requests");
          if (shift.allow_draft) scopes.push("draft");
          if (shift.allow_post_publish) scopes.push("post-publish");
          const shiftScopes = scopes.join(", ") || "None";
          const typeLabel = shift.is_time_off ? "(Time-Off)" : "(Shift)";

          // Styling preview values (safe defaults if fields missing)
          const fill = shift.fill_color || "#f7f7f7";
          const text = shift.text_color || "#000000";
          const weight = shift.text_bold ? "700" : "600";
          const fontStyle = shift.text_italic ? "italic" : "normal";
          
          return `
            <div style="padding:12px; border-bottom:1px solid var(--line); display:flex; align-items:center; justify-content:space-between; gap:12px;">
              <div style="flex:1;">
                <div style="display:inline-block; padding:4px 10px; border-radius:6px; margin-bottom:8px; background:${fill}; color:${text}; border:1px solid #ccc; font-size:12px; font-weight:${weight}; font-style:${fontStyle};">
                  ${escapeHtml(shift.code)} – ${escapeHtml(shift.label)} (${shift.hours_value}h) ${typeLabel}
                </div>
                <div style="font-size:11px; color:var(--muted); margin:4px 0;">Hours: ${escapeHtml(hours)}</div>
                <div style="font-size:11px; color:var(--muted); margin:4px 0;">Staff Groups: ${escapeHtml(staffGroups)}</div>
                <div style="font-size:11px; color:var(--muted); margin:4px 0;">Scopes: ${escapeHtml(shiftScopes)}</div>
              </div>
              <div style="display:flex; gap:8px;">
                <button class="btn" onclick="editShift('${escapeHtml(shift.id)}')">Edit</button>
                <button class="btn" onclick="deleteShift('${escapeHtml(shift.id)}', '${escapeHtml(shift.code)}')" style="background:#ef4444; color:#fff; border-color:#ef4444;">Delete</button>
              </div>
            </div>
          `;
        }).join("");

        if ((shifts || []).length === 0) {
          list.innerHTML = `<div style="padding:20px; text-align:center; color:var(--muted);">No shifts found.</div>`;
        }
      } catch (e) {
        console.error("Failed to load shifts", e);
        const list = document.getElementById("shiftsList");
        if (list) list.innerHTML = `<div style="padding:20px; text-align:center; color:var(--muted);">Failed to load shifts: ${e.message || e}</div>`;
      }
    }

    let allShifts = [];
    let currentEditingShiftId = null;

    function updateShiftPreview(){
      const preview = document.getElementById("editShiftPreview");
      if (!preview) return;
      const fillColor = document.getElementById("editShiftFill")?.value || "#ffffff";
      const textColor = document.getElementById("editShiftText")?.value || "#000000";
      const bold = document.getElementById("editShiftBold")?.checked || false;
      const italic = document.getElementById("editShiftItalic")?.checked || false;
      preview.style.backgroundColor = fillColor;
      preview.style.color = textColor;
      preview.style.fontWeight = bold ? "700" : "600";
      preview.style.fontStyle = italic ? "italic" : "normal";
    }

    function updateNewShiftPreview(){
      const preview = document.getElementById("newShiftPreview");
      if (!preview) return;
      const fillColor = document.getElementById("newShiftFill")?.value || "#ffffff";
      const textColor = document.getElementById("newShiftText")?.value || "#000000";
      const bold = document.getElementById("newShiftBold")?.checked || false;
      const italic = document.getElementById("newShiftItalic")?.checked || false;
      preview.style.backgroundColor = fillColor;
      preview.style.color = textColor;
      preview.style.fontWeight = bold ? "700" : "600";
      preview.style.fontStyle = italic ? "italic" : "normal";
    }

    window.editShift = async function(shiftId){
      console.log("[EDIT SHIFT] Called with ID:", shiftId);
      currentEditingShiftId = shiftId;
      const shift = allShifts.find(s => s.id == shiftId); // Use == instead of === for type coercion
      if (!shift) {
        console.error("[EDIT SHIFT] Shift not found:", shiftId);
        alert("Shift not found!");
        return;
      }

      console.log("[EDIT SHIFT] Found shift:", shift);

      try {
        // NEW schema: allowed_staff_groups is comma-separated string
        const staffGroups = (shift.allowed_staff_groups || "").split(",").map(g => g.trim()).filter(Boolean);

        console.log("[EDIT SHIFT] Staff groups:", staffGroups);

        document.getElementById("editShiftTitle").textContent = `Edit Shift: ${shift.code}`;
        document.getElementById("editShiftCode").value = shift.code;
        const labelField = document.getElementById("editShiftLabel");
        labelField.value = shift.label || "";
        document.getElementById("editShiftStart").value = shift.start_time || "";
        document.getElementById("editShiftEnd").value = shift.end_time || "";
        document.getElementById("editShiftHours").value = shift.hours_value || "";
        document.getElementById("editShiftNA").checked = staffGroups.includes("NA");
        document.getElementById("editShiftSN").checked = staffGroups.includes("Nurse");
        document.getElementById("editShiftCN").checked = staffGroups.includes("CN");
        document.getElementById("editShiftRequests").checked = shift.allow_requests || false;
        document.getElementById("editShiftRotaDraft").checked = shift.allow_draft || false;
        document.getElementById("editShiftRotaPost").checked = shift.allow_post_publish || false;
        document.getElementById("editShiftIsTimeOff").checked = shift.is_time_off || false;
        
        // Load styling fields
        document.getElementById("editShiftFill").value = shift.fill_color || "#ffffff";
        document.getElementById("editShiftText").value = shift.text_color || "#000000";
        document.getElementById("editShiftBold").checked = shift.text_bold || false;
        document.getElementById("editShiftItalic").checked = shift.text_italic || false;

        console.log("[EDIT SHIFT] Form fields populated, opening modal");
        document.getElementById("editShiftModal").style.display = "block";
        // Clear selection and focus on label field for editing
        labelField.setSelectionRange(0, 0);
        labelField.focus();
        updateShiftPreview();
      } catch (e) {
        console.error("[EDIT SHIFT] Error:", e);
        alert("Failed to open edit form: " + e.message);
      }
    };

    window.saveShift = async function(){
      console.log("[SAVE SHIFT] Called, currentEditingShiftId:", currentEditingShiftId);
      if (!currentEditingShiftId) {
        alert("No shift selected for editing.");
        return;
      }
      const shift = allShifts.find(s => s.id == currentEditingShiftId); // Use == for type coercion
      if (!shift) {
        alert("Shift not found in catalog.");
        return;
      }

      try {
        // NEW schema: allowed_staff_groups is comma-separated string
        const staffGroups = [];
        if (document.getElementById("editShiftNA").checked) staffGroups.push("NA");
        if (document.getElementById("editShiftSN").checked) staffGroups.push("Nurse");
        if (document.getElementById("editShiftCN").checked) staffGroups.push("CN");

        // Styling fields now saved (columns exist in shifts table)
        const updateData = {
          label: document.getElementById("editShiftLabel").value,
          start_time: document.getElementById("editShiftStart").value || null,
          end_time: document.getElementById("editShiftEnd").value || null,
          hours_value: parseFloat(document.getElementById("editShiftHours").value) || 0,
          allowed_staff_groups: staffGroups.join(","),
          allow_requests: document.getElementById("editShiftRequests").checked,
          allow_draft: document.getElementById("editShiftRotaDraft").checked,
          allow_post_publish: document.getElementById("editShiftRotaPost").checked,
          is_time_off: document.getElementById("editShiftIsTimeOff").checked,
          fill_color: document.getElementById("editShiftFill").value || null,
          text_color: document.getElementById("editShiftText").value || null,
          text_bold: document.getElementById("editShiftBold").checked,
          text_italic: document.getElementById("editShiftItalic").checked
        };
        console.log("[SAVE SHIFT] Update data with styling:", updateData);

        console.log("[SAVE SHIFT] Update data:", updateData);
        console.log("[SAVE SHIFT] Shift ID:", currentEditingShiftId);

        const { data: result, error: updateErr } = await supabaseClient.rpc("admin_upsert_shift", {
          p_token: currentToken,
          p_shift_id: currentEditingShiftId,
          p_code: document.getElementById("editShiftCode").value,
          p_label: updateData.label,
          p_hours_value: updateData.hours_value,
          p_start_time: updateData.start_time,
          p_end_time: updateData.end_time,
          p_day_or_night: updateData.day_or_night,
          p_allowed_staff_groups: updateData.allowed_staff_groups,
          p_allow_requests: updateData.allow_requests,
          p_allow_draft: updateData.allow_draft,
          p_allow_post_publish: updateData.allow_post_publish,
          p_fill_color: updateData.fill_color,
          p_text_color: updateData.text_color,
          p_text_bold: updateData.text_bold,
          p_text_italic: updateData.text_italic,
          p_is_time_off: updateData.is_time_off
        });

        console.log("[SAVE SHIFT] Update response - data:", result, "error:", updateErr);

        if (updateErr) throw updateErr;

        alert("Shift updated successfully!");
        document.getElementById("editShiftModal").style.display = "none";
        currentEditingShiftId = null;
        await loadShiftsCatalogue();
      } catch (e) {
        console.error("[SAVE SHIFT] Error:", e);
        alert("Failed to save shift: " + e.message);
      }
    };

    window.deleteShift = async function(shiftId, shiftCode){
      if (!confirm(`Are you sure you want to delete shift "${shiftCode}"?\n\nThis action cannot be undone.`)) {
        return;
      }

      try {
        const { error: deleteErr } = await supabaseClient.rpc("admin_delete_shift", {
          p_token: currentToken,
          p_shift_id: shiftId
        });
        
        if (deleteErr) throw deleteErr;

        alert(`Shift "${shiftCode}" deleted successfully!`);
        await loadShiftsCatalogue();
      } catch (e) {
        console.error("Failed to delete shift", e);
        alert("Failed to delete shift: " + e.message);
      }
    };

    window.createNewShift = async function(){
      const code = document.getElementById("newShiftCode")?.value?.trim();
      const label = document.getElementById("newShiftLabel")?.value?.trim();
      
      if (!code || !label) {
        alert("Code and Label are required.");
        return;
      }

      try {
        // NEW schema: allowed_staff_groups is comma-separated string
        const staffGroups = [];
        if (document.getElementById("newShiftNA").checked) staffGroups.push("NA");
        if (document.getElementById("newShiftSN").checked) staffGroups.push("Nurse");
        if (document.getElementById("newShiftCN").checked) staffGroups.push("CN");

        const { data: newShiftId, error: insertErr } = await supabaseClient.rpc("admin_upsert_shift", {
          p_token: currentToken,
          p_shift_id: null,
          p_code: code,
          p_label: label,
          p_hours_value: parseFloat(document.getElementById("newShiftHours").value) || 0,
          p_start_time: document.getElementById("newShiftStart").value || null,
          p_end_time: document.getElementById("newShiftEnd").value || null,
          p_day_or_night: "day",
          p_allowed_staff_groups: staffGroups.join(","),
          p_allow_requests: document.getElementById("newShiftRequests").checked,
          p_allow_draft: document.getElementById("newShiftRotaDraft").checked,
          p_allow_post_publish: document.getElementById("newShiftRotaPost").checked,
          p_fill_color: document.getElementById("newShiftFill").value || null,
          p_text_color: document.getElementById("newShiftText").value || null,
          p_text_bold: document.getElementById("newShiftBold").checked,
          p_text_italic: document.getElementById("newShiftItalic").checked,
          p_is_time_off: document.getElementById("newShiftIsTimeOff").checked
        });
        if (insertErr) throw insertErr;
        if (!newShiftId) throw new Error("Failed to create shift");

        alert("Shift created successfully!");
        document.getElementById("createShiftModal").style.display = "none";
        clearCreateShiftForm();
        await loadShiftsCatalogue();
      } catch (e) {
        console.error("Failed to create shift", e);
        alert("Failed to create shift: " + e.message);
      }
    };

    function clearCreateShiftForm(){
      document.getElementById("newShiftCode").value = "";
      document.getElementById("newShiftLabel").value = "";
      document.getElementById("newShiftStart").value = "";
      document.getElementById("newShiftEnd").value = "";
      document.getElementById("newShiftHours").value = "";
      document.getElementById("newShiftNA").checked = false;
      document.getElementById("newShiftSN").checked = false;
      document.getElementById("newShiftCN").checked = false;
      document.getElementById("newShiftIsTimeOff").checked = false;
      document.getElementById("newShiftFill").value = "#ffffff";
      document.getElementById("newShiftText").value = "#000000";
      document.getElementById("newShiftBold").checked = false;
      document.getElementById("newShiftItalic").checked = false;
      document.getElementById("newShiftRequests").checked = false;
      document.getElementById("newShiftRotaDraft").checked = false;
      document.getElementById("newShiftRotaPost").checked = false;
      document.getElementById("newShiftAvailable").checked = false;
      updateNewShiftPreview();
    }
    adminCreateUserBtn?.addEventListener("click", createUser);
    adminAddUserCancelBtn?.addEventListener("click", clearUserAddForm);

    adminUserSearch?.addEventListener("input", renderAdminUsers);
    adminShowInactiveUsers?.addEventListener("change", renderAdminUsers);
    adminAddUserBtn?.addEventListener("click", openAddUserSection);
    adminCancelUserEditBtn?.addEventListener("click", clearUserEditor);
    
    // Auto-save on Name change
    adminEditUserName?.addEventListener("change", saveUser);
    
    // Auto-save on Role change
    adminEditUserRole?.addEventListener("change", saveUser);
    
    // PIN save button (explicit save only)
    document.getElementById("adminSaveUserPinBtn")?.addEventListener("click", saveUserPin);
    
    // Preferences auto-save
    const savePrefsDebounce = debounce(() => saveAdminPreferences(), 500);
    adminPrefShiftClustering?.addEventListener("input", () => {
      setAdminPref(adminPrefShiftClustering, adminPrefShiftClusteringValue, adminPrefShiftClustering.value);
      savePrefsDebounce();
    });
    adminPrefNightAppetite?.addEventListener("input", () => {
      setAdminPref(adminPrefNightAppetite, adminPrefNightAppetiteValue, adminPrefNightAppetite.value);
      savePrefsDebounce();
    });
    adminPrefWeekendAppetite?.addEventListener("input", () => {
      setAdminPref(adminPrefWeekendAppetite, adminPrefWeekendAppetiteValue, adminPrefWeekendAppetite.value);
      savePrefsDebounce();
    });
    adminPrefLeaveAdjacency?.addEventListener("input", () => {
      setAdminPref(adminPrefLeaveAdjacency, adminPrefLeaveAdjacencyValue, adminPrefLeaveAdjacency.value);
      savePrefsDebounce();
    });

    // Capability checkbox auto-save
    const saveCapabilitiesDebounce = debounce(() => saveAdminPreferences(), 500);
    adminCanBeInChargeDay?.addEventListener("change", saveCapabilitiesDebounce);
    adminCanBeInChargeNight?.addEventListener("change", saveCapabilitiesDebounce);
    adminCannotBeSecondDay?.addEventListener("change", saveCapabilitiesDebounce);
    adminCannotBeSecondNight?.addEventListener("change", saveCapabilitiesDebounce);
    adminCanWorkNights?.addEventListener("change", saveCapabilitiesDebounce);

    // Pattern selector listeners
    document.getElementById("adminUserPattern")?.addEventListener("change", () => {
      updateAnchorDateVisibility();
      saveUserPattern();
    });
    
    document.getElementById("adminUserAnchorDate")?.addEventListener("change", saveUserPattern);

    adminUsersList?.addEventListener("click", (e) => {
      const btn = e.target.closest("button[data-act]");
      if (!btn) return;
      const id = btn.dataset.id;
      const act = btn.dataset.act;
      if (act === "edit") {
        startEditUser(id);
        loadUserPermissionGroups(id);
      }
      if (act === "toggle") toggleUserActive(id);
    });

    // Prompt when Edit user tab is clicked without a user selected
    document.addEventListener("click", (e) => {
      const editUserBtn = e.target.closest("button[data-users-page='edit']");
      if (editUserBtn && !adminEditingUserId) {
        e.preventDefault();
        e.stopPropagation();
        alert("Please select a user from the View users list first.");
      }
    }, true);

    adminEditUserSearch?.addEventListener("input", () => {
      renderAdminUserSelectOptions(adminEditUserSearch.value);
    });

    adminEditUserSelect?.addEventListener("change", () => {
      const id = adminEditUserSelect.value;
      if (id) {
        startEditUser(id);
        loadUserPermissionGroups(id);
      }
    });

    adminUserPermissionGroups?.addEventListener("change", (e) => {
      const chk = e.target.closest("input[data-perm-group]");
      if (!chk) return;
      const userId = adminEditingUserId;
      if (!userId) return alert("Select a user first.");
      saveUserPermissionGroups(userId);
    });

    // Shift catalogue event listeners
    document.getElementById("createShiftBtn")?.addEventListener("click", () => {
      clearCreateShiftForm();
      document.getElementById("createShiftModal").style.display = "block";
    });

    // Add style preview listeners for create form
    ["newShiftFill", "newShiftText", "newShiftBold", "newShiftItalic"].forEach(id => {
      const elem = document.getElementById(id);
      if (elem) {
        elem.addEventListener("change", updateNewShiftPreview);
        elem.addEventListener("input", updateNewShiftPreview);
      }
    });

    // Add style preview listeners for edit form
    ["editShiftFill", "editShiftText", "editShiftBold", "editShiftItalic"].forEach(id => {
      const elem = document.getElementById(id);
      if (elem) {
        elem.addEventListener("change", updateShiftPreview);
        elem.addEventListener("input", updateShiftPreview);
      }
    });

    document.getElementById("createShiftSubmitBtn")?.addEventListener("click", createNewShift);
    document.getElementById("closeCreateShiftBtn")?.addEventListener("click", () => {
      document.getElementById("createShiftModal").style.display = "none";
      clearCreateShiftForm();
    });

    document.getElementById("saveShiftBtn")?.addEventListener("click", saveShift);
    document.getElementById("closeEditShiftBtn")?.addEventListener("click", () => {
      document.getElementById("editShiftModal").style.display = "none";
      currentEditingShiftId = null;
    });

    // Close modals when clicking outside
    document.getElementById("editShiftModal")?.addEventListener("click", (e) => {
      if (e.target.id === "editShiftModal") {
        e.target.style.display = "none";
        currentEditingShiftId = null;
      }
    });

    document.getElementById("createShiftModal")?.addEventListener("click", (e) => {
      if (e.target.id === "createShiftModal") {
        e.target.style.display = "none";
        clearCreateShiftForm();
      }
    });

    console.log("[ADMIN.JS] Attaching load listener");
    window.addEventListener("load", async () => {
      console.log("[ADMIN.JS] Load event fired, calling ensureCurrentUser");
      await ensureCurrentUser();
      console.log("[ADMIN.JS] ensureCurrentUser done, calling loadLoginUsers");
      await loadLoginUsers();
      const activeLink = document.querySelector(".nav a.is-active");
      const panelId = activeLink?.dataset.panel || navLinks[0]?.dataset.panel;
      if (panelId) showPanel(panelId);
    });

    adminLoginBtn?.addEventListener("click", adminLogin);
    adminLoginPin?.addEventListener("keydown", (e) => {
      if (e.key === "Enter") adminLogin();
    });

    // === NOTICES ADMIN WIRING ===
    const adminNoticeSearch = document.getElementById("adminNoticeSearch");
    const adminShowInactiveNotices = document.getElementById("adminShowInactiveNotices");
    const adminNewNoticeBtn = document.getElementById("adminNewNoticeBtn");
    const adminNoticesList = document.getElementById("adminNoticesList");
    const adminNoticeModal = document.getElementById("adminNoticeModal");
    const adminNoticeTitle = document.getElementById("adminNoticeTitle");
    const adminNoticeTitleInput = document.getElementById("adminNoticeTitleInput");
    const adminNoticeSave = document.getElementById("adminNoticeSave");
    const adminNoticeCancel = document.getElementById("adminNoticeCancel");
    const noticeTargetAll = document.getElementById("noticeTargetAll");
    const noticeRoleChks = Array.from(document.querySelectorAll(".notice-role-chk"));
    const noticesPages = Array.from(document.querySelectorAll(".notices-page"));
    const noticesPageTabs = Array.from(document.querySelectorAll(".subtab[data-notices-page]"));

    let adminNoticesCache = [];
    let editingNotice = null;
    let quillEnglish = null;
    let quillSpanish = null;

    // Initialize Quill editors
    function initQuillEditors() {
      if (!window.Quill) {
        console.warn("Quill not loaded yet");
        return;
      }
      if (!quillEnglish && document.getElementById("quillEnglish")) {
        quillEnglish = new Quill('#quillEnglish', { theme: 'snow' });
      }
      if (!quillSpanish && document.getElementById("quillSpanish")) {
        quillSpanish = new Quill('#quillSpanish', { theme: 'snow' });
      }
    }

    // Initialize Quill after admin page load
    setTimeout(() => {
      if (document.getElementById("quillEnglish")) {
        initQuillEditors();
      }
    }, 500);

    function showNoticesPage(id){
      noticesPages.forEach(page => {
        page.style.display = page.id === `noticesPage${id[0].toUpperCase()}${id.slice(1)}` ? "block" : "none";
      });
      noticesPageTabs.forEach(tab => {
        tab.classList.toggle("is-active", tab.dataset.noticesPage === id);
      });
      if (id === "edit" && (!quillEnglish || !quillSpanish)) {
        initQuillEditors();
      }
    }

    noticesPageTabs.forEach(tab => {
      tab.addEventListener("click", () => {
        showNoticesPage(tab.dataset.noticesPage);
      });
    });

    adminNewNoticeBtn?.addEventListener("click", () => {
      if (!requirePermission("notices.create", "Permission required to create notices.")) return;
      clearNoticeEditor();
      showNoticesPage("edit");
    });

    adminNoticeSearch?.addEventListener("input", () => renderAdminNotices());
    adminShowInactiveNotices?.addEventListener("change", () => renderAdminNotices());

    adminNoticeSave?.addEventListener("click", async () => {
      if (!requirePermission("notices.edit", "Permission required to save notices.")) return;
      
      const title = adminNoticeTitleInput.value.trim();
      const body_en = quillEnglish ? quillEnglish.root.innerHTML.trim() : "";
      const body_es = quillSpanish ? quillSpanish.root.innerHTML.trim() : "";

      if (!title) return alert("Title required.");

      const targets = readNoticeTargetsFromUI();

      try {
        adminNoticeSave.disabled = true;

        const payload = {
          id: editingNotice?.id || null,
          title: title,
          body_en: body_en,
          body_es: body_es,
          target_all: targets.target_all,
          target_roles: targets.target_roles
        };

        await adminUpsertNotice(payload);

        await loadAdminNotices();
        showNoticesPage("view");
        alert("Notice saved.");
      } catch (e) {
        console.error(e);
        alert("Failed to save notice. Check console.");
      } finally {
        adminNoticeSave.disabled = false;
      }
    });

    adminNoticeCancel?.addEventListener("click", () => {
      showNoticesPage("view");
    });

    // Ack expansion toggle handler
    adminNoticesList?.addEventListener("click", async (e) => {
      const ackBtn = e.target.closest("[data-ack-toggle]");
      if (ackBtn) {
        e.preventDefault();

        const noticeId = ackBtn.dataset.ackToggle;
        const box = document.getElementById(`ack-list-${noticeId}`);
        if (!box) return;

        const isOpen = box.style.display === "block";
        box.style.display = isOpen ? "none" : "block";

        if (ackBtn && ackBtn.setAttribute) ackBtn.setAttribute('aria-expanded', String(!isOpen));

        if (isOpen) return;

        if (box.dataset.loaded === "1") return;

        box.innerHTML = `<div class="subtitle">Loading…</div>`;

        try {
          const rows = await fetchNoticeAcksForAdmin(noticeId);

          if (!rows.length) {
            box.innerHTML = `<div class="subtitle">Nobody yet.</div>`;
          } else {
            box.innerHTML = `
              <div style="display:flex; flex-wrap:wrap; gap:8px;">
                ${rows.map(r => `
                  <span class="ack-pill"
                        style="padding:6px 10px; border:1px solid #e5e7eb; border-radius:999px; font-size:12px;">
                    ${escapeHtml(r.name || "Unknown")}
                    <span class="muted" style="margin-left:6px;">
                      ${r.acknowledged_at
                        ? new Date(r.acknowledged_at).toLocaleString("en-GB")
                        : ""}
                    </span>
                  </span>
                `).join("")}
              </div>
            `;

            try {
              const countSpan = document.querySelector(`[data-ack-count="${noticeId}"]`);
              if (countSpan && Number(countSpan.textContent) !== rows.length) {
                console.debug('Mismatch detected: fixing ack count for', noticeId, 'to', rows.length);
                countSpan.textContent = String(rows.length);
                const noticeObj = adminNoticesCache.find(n => String(n.id) === String(noticeId));
                if (noticeObj) noticeObj.ack_count = rows.length;
              }
            } catch (e) { console.warn('failed to update count fallback', e); }
          }

          box.dataset.loaded = "1";
        } catch (err) {
          console.error(err);
          box.innerHTML = `<div class="subtitle">Failed to load.</div>`;
        }

        return;
      }

      // Handle row action buttons
      const row = e.target.closest(".notice-row");
      if (!row) return;

      const act = e.target.closest("button")?.dataset.act;
      if (!act) return;

      const id = row.dataset.id;
      const notice = adminNoticesCache.find(n => String(n.id) === String(id));
      if (!notice) return;

      if (act === "edit") {
        if (!requirePermission("notices.edit", "Permission required to edit notices.")) return;
        openAdminNoticeEditor(notice);
      }

      if (act === "toggle") {
        if (!requirePermission("notices.toggle_active", "Permission required to toggle notice visibility.")) return;
        await toggleAdminNoticeActive(notice);
      }

      if (act === "delete") {
        if (!requirePermission("notices.delete", "Permission required to delete notices.")) return;
        await deleteAdminNotice(notice);
      }
    });

    function clearNoticeEditor(){
      editingNotice = null;

      if (adminNoticeTitleInput) adminNoticeTitleInput.value = "";
      if (quillEnglish) quillEnglish.setContents([]);
      if (quillSpanish) quillSpanish.setContents([]);

      if (noticeTargetAll) noticeTargetAll.checked = true;
      noticeRoleChks.forEach(chk => chk.checked = false);
    }

    async function adminFetchNoticeAcks(noticeId){
      const { data, error } = await supabaseClient
        .rpc("admin_get_notice_acks", { p_token: currentToken, p_notice_id: noticeId });

      if (error) throw error;

      const res = Array.isArray(data) ? (data[0] || { acked: [], pending: [] }) : (data || { acked: [], pending: [] });
      return res.acked || [];
    }

    async function fetchNoticeAcksForAdmin(noticeId){
      return adminFetchNoticeAcks(noticeId);
    }

    function hydrateNoticeTargetsFromNotice(notice){
      const targetAll = !!notice.target_all;
      const roles = Array.isArray(notice.target_roles) ? notice.target_roles.map(Number) : [];

      if (noticeTargetAll) noticeTargetAll.checked = targetAll;
      noticeRoleChks.forEach(chk => {
        chk.checked = roles.includes(Number(chk.value));
      });
    }

    function readNoticeTargetsFromUI(){
      let targetAll = !!noticeTargetAll?.checked;
      const roles = noticeRoleChks
        .filter(chk => chk.checked)
        .map(chk => Number(chk.value))
        .filter(n => [1,2,3].includes(n));

      if (roles.length > 0) targetAll = false;

      return { target_all: targetAll, target_roles: roles };
    }

    function openAdminNoticeEditor(notice){
      if (!currentUser?.is_admin && !hasPermission("notices.edit")) {
        alert("Permission required to edit notices.");
        return;
      }

      if (!notice){
        clearNoticeEditor();
        editingNotice = null;
        showNoticesPage("edit");
        return;
      }

      editingNotice = notice;

      if (adminNoticeTitleInput) adminNoticeTitleInput.value = notice.title || "";
      
      if (quillEnglish) quillEnglish.root.innerHTML = notice.body_en || "";
      if (quillSpanish) quillSpanish.root.innerHTML = notice.body_es || "";

      hydrateNoticeTargetsFromNotice(notice);

      showNoticesPage("edit");
    }

    function renderAdminNotices(){
      if (!adminNoticesList) return;

      const q = (adminNoticeSearch?.value || "").trim().toLowerCase();
      const showInactive = !!adminShowInactiveNotices?.checked;

      let rows = adminNoticesCache.slice();
      if (!showInactive) rows = rows.filter(n => n.is_active !== false);
      if (q) rows = rows.filter(n => (n.title || "").toLowerCase().includes(q));

      if (!rows.length){
        adminNoticesList.innerHTML =
          `<div class="subtitle" style="padding:12px;">No notices.</div>`;
        return;
      }

      adminNoticesList.innerHTML = rows.map(n => {
        const createdBy = escapeHtml(n.users?.name || "Unknown");
        const when = n.updated_at
          ? new Date(n.updated_at).toLocaleDateString("en-GB")
          : "";

        const ackCount = n.ack_count ?? 0;
        const ackTotal = n.ack_total ?? 0;

        return `
          <div class="notice-row"
               data-id="${n.id}"
               style="padding:12px; border-bottom:1px solid #eee;">

            <div style="display:flex; gap:10px; align-items:flex-start;">
              <div style="flex:1; min-width:0;">
                <div style="font-weight:800;">${escapeHtml(n.title)}</div>

                <div style="font-size:11px; color:#667085; margin-top:4px;">
                  v${n.version}
                  · ${createdBy}
                  · ${when}
                  ${!n.is_active
                    ? `<span class="notice-pill" style="margin-left:6px;">Inactive</span>`
                    : ``}
                </div>
              </div>

              <div style="display:flex; gap:6px;">
                <button data-act="edit">Edit</button>
                <button data-act="toggle">${n.is_active ? "Hide" : "Unhide"}</button>
                <button data-act="delete">Delete</button>
              </div>
            </div>

            <!-- Acknowledged By (expandable) -->
            <div class="ack-summary" style="margin-top:8px;">
              <button type="button"
                      class="ghost"
                      data-ack-toggle="${n.id}"
                      style="padding:6px 10px; border-radius:999px; font-size:12px; background:transparent; border:none; cursor:pointer; color:#64748b;">
                Acknowledged:
                <span data-ack-count="${n.id}">${ackCount ?? "–"}</span>
                <span class="muted"> / </span>
                <span data-ack-total="${n.id}">${ackTotal ?? "–"}</span>
                <span class="muted"> · View</span>
              </button>

              <div id="ack-list-${n.id}"
                   class="ack-list"
                   style="display:none; margin-top:8px; padding:10px; border:1px solid #e5e7eb; border-radius:12px;">
                <div class="subtitle">Loading…</div>
              </div>
            </div>

          </div>
        `;
      }).join("");
    }

    async function loadAdminNotices(){
      if (!currentUser?.is_admin && !hasPermission("notices.view_admin")) return;

      const { data, error } = await supabaseClient.rpc("admin_get_all_notices", {
        p_token: currentToken
      });

      if (error){
        console.error(error);
        alert("Failed to load notices: " + err.message);
        return;
      }

      const notices = data || [];
      let usersMap = new Map();
      try {
        const { data: users } = await supabaseClient.rpc("admin_get_users", {
          p_token: currentToken,
          p_include_inactive: true
        });
        usersMap = new Map((users || []).map(u => [String(u.id), u.name]));
      } catch (e) {
        usersMap = new Map();
      }

      adminNoticesCache = notices.map(n => ({
        ...n,
        users: { name: usersMap.get(String(n.created_by)) || "Unknown" }
      }));

      // Fetch ack counts
      try {
        const ids = (adminNoticesCache || []).map(n => n.id).filter(Boolean);
        if (ids.length) {
          const counts = await adminFetchNoticeAckCounts(ids);
          const map = new Map((counts || []).map(r => [String(r.notice_id), { ack_count: Number(r.ack_count), ack_total: Number(r.ack_total) }]));
          adminNoticesCache.forEach(n => {
            const c = map.get(String(n.id));
            n.ack_count = c?.ack_count ?? 0;
            n.ack_total = c?.ack_total ?? 0;
          });
        }
      } catch (err) {
        console.error('Failed to fetch notice ack counts', err);
      }

      renderAdminNotices();
    }

    async function adminFetchNoticeAckCounts(noticeIds){
      if (!Array.isArray(noticeIds) || noticeIds.length === 0) return [];

      const { data, error } = await supabaseClient.rpc("admin_notice_ack_counts", {
        p_token: currentToken,
        p_notice_ids: noticeIds
      });

      if (error) throw error;

      return data || [];
    }

    async function adminUpsertNotice(payload){
      await requireAdminPin();

      const targetRoles = Array.isArray(payload.target_roles) ? payload.target_roles : [];
      const targetAll = !!payload.target_all && targetRoles.length === 0;

      const { data, error } = await supabaseClient.rpc("admin_upsert_notice", {
        p_token: currentToken,
        p_notice_id: payload.id || null,
        p_title: payload.title,
        p_body_en: payload.body_en,
        p_body_es: payload.body_es,
        p_target_all: targetAll,
        p_target_roles: targetRoles
      });

      if (error) throw error;
      return data;
    }

    async function toggleAdminNoticeActive(notice){
      await requireAdminPin();

      const next = (notice.is_active === false) ? true : false;
      const ok = confirm(`${next ? "Unhide" : "Hide"} "${notice.title}"?`);
      if (!ok) return;

      const { error } = await supabaseClient.rpc("admin_set_notice_active", {
        p_token: currentToken,
        p_notice_id: notice.id,
        p_active: next
      });

      if (error) throw error;

      await loadAdminNotices();
    }

    async function deleteAdminNotice(notice){
      await requireAdminPin();

      const ok = confirm(`Delete "${notice.title}"?\n\nThis cannot be undone.`);
      if (!ok) return;

      const { error } = await supabaseClient.rpc("admin_delete_notice", {
        p_token: currentToken,
        p_notice_id: notice.id
      });

      if (error) throw error;

      await loadAdminNotices();
    }

    adminUsersReorderList?.addEventListener("dragstart", (e) => {
      const userRow = e.target.closest('.user-row[draggable="true"]');
      if (!userRow) return;
      draggedElement = userRow;
      draggedRoleId = userRow.dataset.roleId;
      userRow.classList.add('dragging');
      e.dataTransfer.effectAllowed = 'move';
    });

    adminUsersReorderList?.addEventListener("dragend", () => {
      adminUsersReorderList.querySelectorAll('.user-row').forEach(row => row.classList.remove('dragging', 'drag-over'));
      draggedElement = null;
      draggedRoleId = null;
    });

    adminUsersReorderList?.addEventListener("dragover", (e) => {
      e.preventDefault();
      const userRow = e.target.closest('.user-row[draggable="true"]');
      if (!userRow || !draggedElement) return;
      if (userRow.dataset.roleId !== draggedRoleId) return;
      if (userRow === draggedElement) return;
      adminUsersReorderList.querySelectorAll('.user-row').forEach(row => row.classList.remove('drag-over'));
      userRow.classList.add('drag-over');
    });

    adminUsersReorderList?.addEventListener("drop", async (e) => {
      e.preventDefault();
      const targetRow = e.target.closest('.user-row[draggable="true"]');
      if (!targetRow || !draggedElement) return;
      if (targetRow.dataset.roleId !== draggedRoleId) return;
      if (targetRow === draggedElement) return;
      targetRow.classList.remove('drag-over');

      const allRows = Array.from(adminUsersReorderList.querySelectorAll(`.user-row[data-role-id="${draggedRoleId}"]`));
      const draggedIndex = allRows.indexOf(draggedElement);
      const targetIndex = allRows.indexOf(targetRow);
      if (draggedIndex < targetIndex) {
        targetRow.parentNode.insertBefore(draggedElement, targetRow.nextSibling);
      } else {
        targetRow.parentNode.insertBefore(draggedElement, targetRow);
      }
      await updateUserDisplayOrder(draggedRoleId);
    });

    // Main users list (View page) - same drag-and-drop functionality
    adminUsersList?.addEventListener("dragstart", (e) => {
      const userRow = e.target.closest('.user-row[draggable="true"]');
      if (!userRow) return;
      draggedElement = userRow;
      draggedRoleId = userRow.dataset.roleId;
      userRow.classList.add('dragging');
      e.dataTransfer.effectAllowed = 'move';
    });

    adminUsersList?.addEventListener("dragend", () => {
      adminUsersList.querySelectorAll('.user-row').forEach(row => row.classList.remove('dragging', 'drag-over'));
      draggedElement = null;
      draggedRoleId = null;
    });

    adminUsersList?.addEventListener("dragover", (e) => {
      e.preventDefault();
      const userRow = e.target.closest('.user-row[draggable="true"]');
      if (!userRow || !draggedElement) return;
      if (userRow.dataset.roleId !== draggedRoleId) return;
      if (userRow === draggedElement) return;
      adminUsersList.querySelectorAll('.user-row').forEach(row => row.classList.remove('drag-over'));
      userRow.classList.add('drag-over');
    });

    adminUsersList?.addEventListener("drop", async (e) => {
      e.preventDefault();
      const targetRow = e.target.closest('.user-row[draggable="true"]');
      if (!targetRow || !draggedElement) return;
      if (targetRow.dataset.roleId !== draggedRoleId) return;
      if (targetRow === draggedElement) return;
      targetRow.classList.remove('drag-over');

      const allRows = Array.from(adminUsersList.querySelectorAll(`.user-row[data-role-id="${draggedRoleId}"]`));
      const draggedIndex = allRows.indexOf(draggedElement);
      const targetIndex = allRows.indexOf(targetRow);
      if (draggedIndex < targetIndex) {
        targetRow.parentNode.insertBefore(draggedElement, targetRow.nextSibling);
      } else {
        targetRow.parentNode.insertBefore(draggedElement, targetRow);
      }
      await updateUserDisplayOrder(draggedRoleId);
    });

    // ===== SHIFT SWAPS =====
    const adminSwapSearch = document.getElementById("adminSwapSearch");
    const adminSwapStatusFilter = document.getElementById("adminSwapStatusFilter");
    const adminSwapsPendingList = document.getElementById("adminSwapsPendingList");
    const adminSwapHistorySearch = document.getElementById("adminSwapHistorySearch");
    const adminSwapMethodFilter = document.getElementById("adminSwapMethodFilter");
    const adminSwapsExecutedList = document.getElementById("adminSwapsExecutedList");

    let adminSwapsPendingCache = [];
    let adminSwapsExecutedCache = [];

    function showSwapsPage(id){
      swapsPages.forEach(page => {
        page.style.display = page.id === `swaps${id[0].toUpperCase()}${id.slice(1)}Page` ? "block" : "none";
      });
      swapsPageTabs.forEach(tab => {
        tab.classList.toggle("is-active", tab.dataset.swapsPage === id);
      });
    }

    swapsPageTabs.forEach(tab => {
      tab.addEventListener("click", () => {
        showSwapsPage(tab.dataset.swapsPage);
        if (tab.dataset.swapsPage === "pending") loadAdminSwapsPending();
        if (tab.dataset.swapsPage === "executed") loadAdminSwapsExecuted();
      });
    });

    async function loadAdminSwapsPending(){
      if (!requirePermission("rota.swap", "Permission required to view swaps.")) return;

      try {
        const { data, error } = await supabaseClient.rpc("admin_get_swap_requests", {
          p_token: currentToken
        });

        if (error) throw error;

        adminSwapsPendingCache = (data || []).filter(s => s.status !== 'executed');
        renderAdminSwapsPending();
      } catch (err) {
        console.error(err);
        adminSwapsPendingList.innerHTML = `<div class="subtitle" style="padding:12px; color:#dc2626;">Error loading swaps.</div>`;
      }
    }

    async function loadAdminSwapsExecuted(){
      if (!requirePermission("rota.swap", "Permission required to view swaps.")) return;

      try {
        const { data, error } = await supabaseClient.rpc("admin_get_swap_executions", {
          p_token: currentToken,
          p_period_id: null
        });

        if (error) throw error;

        adminSwapsExecutedCache = data || [];
        renderAdminSwapsExecuted();
      } catch (err) {
        console.error(err);
        adminSwapsExecutedList.innerHTML = `<div class="subtitle" style="padding:12px; color:#dc2626;">Error loading history.</div>`;
      }
    }

    function renderAdminSwapsPending(){
      if (!adminSwapsPendingList) return;

      const q = (adminSwapSearch?.value || "").trim().toLowerCase();
      const filter = adminSwapStatusFilter?.value || "";

      let rows = adminSwapsPendingCache.slice();
      if (filter) rows = rows.filter(s => s.status === filter);
      if (q) {
        rows = rows.filter(s =>
          (s.initiator_name || "").toLowerCase().includes(q) ||
          (s.counterparty_name || "").toLowerCase().includes(q)
        );
      }

      if (!rows.length){
        adminSwapsPendingList.innerHTML = `<div class="subtitle" style="padding:12px;">No pending swaps.</div>`;
        return;
      }

      adminSwapsPendingList.innerHTML = rows.map(s => {
        const statusLabel = {
          'pending': 'Pending counterparty response',
          'accepted_by_counterparty': 'Accepted (awaiting admin approval)',
          'declined_by_counterparty': 'Declined by counterparty'
        }[s.status] || s.status;

        const dateStr1 = new Date(s.initiator_shift_date).toLocaleDateString('en-GB', { weekday: 'short', month: 'short', day: 'numeric' });
        const dateStr2 = new Date(s.counterparty_shift_date).toLocaleDateString('en-GB', { weekday: 'short', month: 'short', day: 'numeric' });

        return `
          <div style="padding:12px; border-bottom:1px solid var(--line); display:flex; gap:12px; align-items:flex-start;">
            <div style="flex:1; min-width:0;">
              <div style="font-weight:600; margin-bottom:4px;">
                ${escapeHtml(s.initiator_name)} ${dateStr1} (${s.initiator_shift_code})
              </div>
              <div style="font-size:11px; color:var(--muted); margin-bottom:4px;">↔ ${escapeHtml(s.counterparty_name)} ${dateStr2} (${s.counterparty_shift_code})</div>
              <div style="font-size:12px; color:var(--muted);">${statusLabel}</div>
            </div>
            ${s.status === 'accepted_by_counterparty' ? `
              <div style="display:flex; gap:6px;">
                <button class="btn small primary" data-swap-approve="${s.id}" type="button">Approve</button>
                <button class="btn small" data-swap-decline="${s.id}" type="button">Decline</button>
              </div>
            ` : ''}
          </div>
        `;
      }).join("");
    }

    function renderAdminSwapsExecuted(){
      if (!adminSwapsExecutedList) return;

      const q = (adminSwapHistorySearch?.value || "").trim().toLowerCase();
      const filter = adminSwapMethodFilter?.value || "";

      let rows = adminSwapsExecutedCache.slice();
      if (filter) rows = rows.filter(s => s.method === filter);
      if (q) {
        rows = rows.filter(s =>
          (s.initiator_name || "").toLowerCase().includes(q) ||
          (s.counterparty_name || "").toLowerCase().includes(q)
        );
      }

      if (!rows.length){
        adminSwapsExecutedList.innerHTML = `<div class="subtitle" style="padding:12px;">No executed swaps.</div>`;
        return;
      }

      adminSwapsExecutedList.innerHTML = rows.map(s => {
        const methodLabel = s.method === 'admin_direct' ? 'Admin Direct' : 'Staff Approved';
        const dateStr1 = new Date(s.initiator_date).toLocaleDateString('en-GB', { weekday: 'short', month: 'short', day: 'numeric' });
        const dateStr2 = new Date(s.counterparty_date).toLocaleDateString('en-GB', { weekday: 'short', month: 'short', day: 'numeric' });
        const execStr = new Date(s.executed_at).toLocaleString('en-GB');

        return `
          <div style="padding:12px; border-bottom:1px solid var(--line);">
            <div style="font-weight:600; margin-bottom:4px;">
              ${escapeHtml(s.initiator_name)} ${dateStr1} (${s.initiator_old_shift} → ${s.initiator_new_shift})
            </div>
            <div style="font-size:11px; color:var(--muted); margin-bottom:4px;">
              ↔ ${escapeHtml(s.counterparty_name)} ${dateStr2} (${s.counterparty_old_shift} → ${s.counterparty_new_shift})
            </div>
            <div style="font-size:11px; color:var(--muted);">
              ${methodLabel} · Authorised by ${escapeHtml(s.authoriser_name)} · ${execStr}
            </div>
          </div>
        `;
      }).join("");
    }

    adminSwapSearch?.addEventListener("input", renderAdminSwapsPending);
    adminSwapStatusFilter?.addEventListener("change", renderAdminSwapsPending);
    adminSwapHistorySearch?.addEventListener("input", renderAdminSwapsExecuted);
    adminSwapMethodFilter?.addEventListener("change", renderAdminSwapsExecuted);

    adminSwapsPendingList?.addEventListener("click", async (e) => {
      const approveBtn = e.target.closest("button[data-swap-approve]");
      if (approveBtn) {
        const swapId = approveBtn.dataset.swapApprove;
        const swap = adminSwapsPendingCache.find(s => String(s.id) === String(swapId));
        if (!swap) return;

        try {
          approveBtn.disabled = true;
          // SECURITY PATCH: Require PIN verification for sensitive operation
          const pinVerified = await promptAdminPinChallenge();
          if (!pinVerified) {
            alert("PIN verification failed.");
            approveBtn.disabled = false;
            return;
          }
          const { data, error } = await supabaseClient.rpc("admin_approve_swap_request", {
            p_token: currentToken,
            p_swap_request_id: swapId
          });

          if (error) throw error;
          if (!data[0]?.success) throw new Error(data[0]?.error_message || "Failed to approve swap");

          await loadAdminSwapsPending();
          await loadAdminSwapsExecuted();
          alert("Swap approved.");
        } catch (err) {
          console.error(err);
          alert("Failed to approve swap. Check console.");
        } finally {
          approveBtn.disabled = false;
        }
        return;
      }

      const declineBtn = e.target.closest("button[data-swap-decline]");
      if (declineBtn) {
        const swapId = declineBtn.dataset.swapDecline;
        if (!confirm("Decline this swap request?")) return;

        try {
          declineBtn.disabled = true;
          // SECURITY PATCH: Require PIN verification for sensitive operation
          const pinVerified = await promptAdminPinChallenge();
          if (!pinVerified) {
            alert("PIN verification failed.");
            declineBtn.disabled = false;
            return;
          }
          const { data, error } = await supabaseClient.rpc("admin_decline_swap_request", {
            p_token: currentToken,
            p_swap_request_id: swapId
          });

          if (error) throw error;
          if (!data[0]?.success) throw new Error(data[0]?.error_message || "Failed to decline swap");

          await loadAdminSwapsPending();
          alert("Swap declined.");
        } catch (err) {
          console.error(err);
          alert("Failed to decline swap. Check console.");
        } finally {
          declineBtn.disabled = false;
        }
      }
    });

    // ========== BANK HOLIDAYS MANAGEMENT ==========
    async function loadBankHolidays() {
      if (!currentToken) return;
      try {
        const selectedYear = parseInt(bhYear.value) || new Date().getFullYear();
        const { data, error } = await supabaseClient.rpc('rpc_list_bank_holidays', {
          p_token: currentToken,
          p_year: selectedYear
        });
        if (error) throw error;
        bhCache = data || [];
        renderBankHolidaysList();
      } catch (err) {
        console.error('Failed to load bank holidays:', err);
        bhAddHelp.textContent = 'Error loading bank holidays: ' + (err?.message || err);
      }
    }

    function renderBankHolidaysList() {
      bhList.innerHTML = '';
      if (bhCache.length === 0) {
        bhList.innerHTML = '<div style="padding:12px; color:var(--muted); font-size:13px;">No bank holidays for this year.</div>';
        return;
      }
      bhCache.forEach(holiday => {
        const row = document.createElement('div');
        row.style.display = 'flex';
        row.style.justifyContent = 'space-between';
        row.style.alignItems = 'center';
        row.style.padding = '12px';
        row.style.borderBottom = '1px solid var(--line)';
        
        const info = document.createElement('div');
        const dateObj = new Date(holiday.holiday_date);
        const dateStr = dateObj.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
        info.innerHTML = `<strong>${holiday.name}</strong><br><span style="font-size:12px; color:var(--muted);">${dateStr}</span>`;
        
        const deleteBtn = document.createElement('button');
        deleteBtn.textContent = 'Delete';
        deleteBtn.className = 'btn';
        deleteBtn.style.whiteSpace = 'nowrap';
        deleteBtn.addEventListener('click', async () => {
          if (!confirm(`Remove "${holiday.name}"?`)) return;
          try {
            const { error } = await supabaseClient.rpc('rpc_delete_bank_holiday', {
              p_token: currentToken,
              p_id: holiday.id
            });
            if (error) throw error;
            await loadBankHolidays();
          } catch (err) {
            alert('Failed to delete: ' + (err?.message || err));
          }
        });
        
        row.appendChild(info);
        row.appendChild(deleteBtn);
        bhList.appendChild(row);
      });
    }

    if (bhYear) {
      bhYear.addEventListener('change', loadBankHolidays);
    }

    if (bhAddBtn) {
      bhAddBtn.addEventListener('click', async () => {
        const dateVal = bhDate.value;
        const nameVal = bhName.value?.trim();
        const yearVal = parseInt(bhYear.value);
        
        bhAddHelp.textContent = '';
        if (!dateVal) {
          bhAddHelp.textContent = 'Please select a date.';
          return;
        }
        if (!nameVal) {
          bhAddHelp.textContent = 'Please enter a holiday name.';
          return;
        }
        
        try {
          bhAddBtn.disabled = true;
          const { data, error } = await supabaseClient.rpc('rpc_add_bank_holiday', {
            p_token: currentToken,
            p_year: yearVal,
            p_date: dateVal,
            p_name: nameVal
          });
          
          if (error) throw error;
          if (!data?.success) throw new Error(data?.error || 'Failed to add bank holiday');
          
          bhDate.value = '';
          bhName.value = '';
          bhAddHelp.textContent = '✓ Bank holiday added.';
          await loadBankHolidays();
        } catch (err) {
          bhAddHelp.textContent = 'Error: ' + (err?.message || err);
        } finally {
          bhAddBtn.disabled = false;
        }
      });
    }

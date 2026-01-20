/**
 * User Account Modal Module
 * Shared component for user account editing across rota.html and requests.html
 * Requires: window.currentUser, window.supabaseClient (via getSupabase())
 */

(function() {
  'use strict';

  function initUserModal() {
    const loginBadge = document.getElementById("loginBadge");
    const userModal = document.getElementById("userModal");
    const userClose = document.getElementById("userClose");
    const userLogout = document.getElementById("userLogout");
    const userSavePin = document.getElementById("userSavePin");
    const userMeta = document.getElementById("userMeta");
    const userSavePrefs = document.getElementById("userSavePrefs");
    const userPrefsErr = document.getElementById("userPrefsErr");
    const userPrefsOk = document.getElementById("userPrefsOk");
    const prefInputs = {
      pref_shift_clustering: document.getElementById("prefShiftClustering"),
      pref_night_appetite: document.getElementById("prefNightAppetite"),
      pref_weekend_appetite: document.getElementById("prefWeekendAppetite"),
      pref_leave_adjacency: document.getElementById("prefLeaveAdjacency"),
    };
    const prefLabels = {
      pref_shift_clustering: document.getElementById("prefShiftClusteringValue"),
      pref_night_appetite: document.getElementById("prefNightAppetiteValue"),
      pref_weekend_appetite: document.getElementById("prefWeekendAppetiteValue"),
      pref_leave_adjacency: document.getElementById("prefLeaveAdjacencyValue"),
    };

    if (!userModal) {
      console.warn('[USER-MODAL] userModal element not found');
      return;
    }

    // Open modal when clicking login badge
    if (loginBadge) {
      loginBadge.addEventListener("click", () => {
        if (userMeta && window.currentUser) {
          userMeta.textContent = window.currentUser.name;
        }
        userModal.style.display = "flex";
        userModal.setAttribute("aria-hidden", "false");
        loadMyPreferences();
      });
    }

    // Close modal
    if (userClose) {
      userClose.addEventListener("click", closeModal);
    }

    // Close on backdrop click
    userModal.addEventListener("click", (e) => {
      if (e.target === userModal) {
        closeModal();
      }
    });

    // Logout from modal
    if (userLogout) {
      userLogout.addEventListener("click", async () => {
        if (typeof logout === 'function') {
          await logout();
        } else {
          console.error('[USER-MODAL] logout function not found');
        }
      });
    }

    // Save PIN
    if (userSavePin) {
      userSavePin.addEventListener("click", savePIN);
    }

    // Save Preferences
    if (userSavePrefs) {
      userSavePrefs.addEventListener("click", savePreferences);
    }

    // Live update preference labels
    Object.entries(prefInputs).forEach(([key, input]) => {
      if (!input) return;
      input.addEventListener("input", () => {
        if (prefLabels[key]) prefLabels[key].textContent = String(input.value || "");
      });
    });

    // Language buttons (if present)
    const langEn = document.getElementById("userLangEn");
    const langEs = document.getElementById("userLangEs");
    
    if (langEn) {
      langEn.addEventListener("click", () => setLanguage('en'));
    }
    
    if (langEs) {
      langEs.addEventListener("click", () => setLanguage('es'));
    }

    // Initialize language buttons state
    updateLanguageButtons();

    // Calendar subscription buttons
    const generateCalBtn = document.getElementById("generateCalendarToken");
    const revokeCalBtn = document.getElementById("revokeCalendarToken");
    const copyCalBtn = document.getElementById("copyCalendarURL");
    const copyWebcalBtn = document.getElementById("copyWebcalURL");

    if (generateCalBtn) {
      generateCalBtn.addEventListener("click", generateCalendarToken);
    }

    if (revokeCalBtn) {
      revokeCalBtn.addEventListener("click", revokeCalendarToken);
    }

    if (copyCalBtn) {
      copyCalBtn.addEventListener("click", () => copyToClipboard('calendarURL'));
    }

    if (copyWebcalBtn) {
      copyWebcalBtn.addEventListener("click", () => copyToClipboard('webcalURL'));
    }

    // Load calendar token status on open
    loadCalendarTokenStatus();
  }

  function closeModal() {
    const userModal = document.getElementById("userModal");
    if (userModal) {
      userModal.style.display = "none";
      userModal.setAttribute("aria-hidden", "true");
      
      // Clear PIN fields
      const oldPin = document.getElementById("userOldPin");
      const newPin = document.getElementById("userNewPin");
      const newPin2 = document.getElementById("userNewPin2");
      
      if (oldPin) oldPin.value = "";
      if (newPin) newPin.value = "";
      if (newPin2) newPin2.value = "";
      
      // Hide messages
      const errEl = document.getElementById("userPinErr");
      const okEl = document.getElementById("userPinOk");
      
      if (errEl) errEl.style.display = "none";
      if (okEl) okEl.style.display = "none";
    }
  }

  async function savePIN() {
    const oldPin = document.getElementById("userOldPin")?.value;
    const newPin = document.getElementById("userNewPin")?.value;
    const newPin2 = document.getElementById("userNewPin2")?.value;
    const errEl = document.getElementById("userPinErr");
    const okEl = document.getElementById("userPinOk");

    if (!errEl || !okEl) return;

    errEl.style.display = "none";
    okEl.style.display = "none";

    // Validation
    if (!oldPin || !newPin || !newPin2) {
      errEl.textContent = "Please fill in all PIN fields";
      errEl.style.display = "block";
      return;
    }

    if (newPin !== newPin2) {
      errEl.textContent = "New PINs do not match";
      errEl.style.display = "block";
      return;
    }

    if (newPin.length !== 4 || !/^\d{4}$/.test(newPin)) {
      errEl.textContent = "PIN must be exactly 4 digits";
      errEl.style.display = "block";
      return;
    }

    try {
      const supabase = typeof getSupabase === 'function' ? getSupabase() : window.supabaseClient;
      
      if (!supabase) {
        throw new Error("Supabase client not available");
      }

      if (!window.currentUser?.id) {
        throw new Error("No current user");
      }

      const { data, error } = await supabase.rpc("change_user_pin", {
        p_user_id: window.currentUser.id,
        p_old_pin: oldPin,
        p_new_pin: newPin
      });

      if (error) throw error;

      if (data === false) {
        errEl.textContent = "Current PIN is incorrect";
        errEl.style.display = "block";
        return;
      }

      // Success
      okEl.textContent = "PIN updated successfully";
      okEl.style.display = "block";
      
      // Clear fields
      document.getElementById("userOldPin").value = "";
      document.getElementById("userNewPin").value = "";
      document.getElementById("userNewPin2").value = "";
      
    } catch (error) {
      console.error("Error changing PIN:", error);
      errEl.textContent = "Failed to change PIN: " + error.message;
      errEl.style.display = "block";
    }
  }

  async function loadMyPreferences() {
    const supabase = typeof getSupabase === 'function' ? getSupabase() : window.supabaseClient;
    if (!supabase || !window.currentUser?.id) return;
    try {
      const { data, error } = await supabase
        .from("users")
        .select("pref_shift_clustering, pref_night_appetite, pref_weekend_appetite, pref_leave_adjacency")
        .eq("id", window.currentUser.id)
        .single();
      if (error) throw error;
      const prefs = data || {};
      const fields = [
        "pref_shift_clustering",
        "pref_night_appetite",
        "pref_weekend_appetite",
        "pref_leave_adjacency"
      ];
      fields.forEach((f) => {
        const val = prefs[f] ?? 3;
        const input = document.getElementById(f === 'pref_shift_clustering' ? 'prefShiftClustering' :
          f === 'pref_night_appetite' ? 'prefNightAppetite' :
          f === 'pref_weekend_appetite' ? 'prefWeekendAppetite' : 'prefLeaveAdjacency');
        const label = document.getElementById(f === 'pref_shift_clustering' ? 'prefShiftClusteringValue' :
          f === 'pref_night_appetite' ? 'prefNightAppetiteValue' :
          f === 'pref_weekend_appetite' ? 'prefWeekendAppetiteValue' : 'prefLeaveAdjacencyValue');
        if (input) input.value = val;
        if (label) label.textContent = String(val);
      });
      const errEl = document.getElementById("userPrefsErr");
      if (errEl) errEl.style.display = "none";
    } catch (err) {
      console.warn("[USER-PREFS] Failed to load preferences", err);
    }
  }

  async function savePreferences() {
    const errEl = document.getElementById("userPrefsErr");
    const okEl = document.getElementById("userPrefsOk");
    if (errEl) errEl.style.display = "none";
    if (okEl) okEl.style.display = "none";

    const supabase = typeof getSupabase === 'function' ? getSupabase() : window.supabaseClient;
    if (!supabase) {
      if (errEl) { errEl.textContent = "Supabase unavailable"; errEl.style.display = "block"; }
      return;
    }
    if (!window.currentUser?.id || !window.currentToken) {
      if (errEl) { errEl.textContent = "Missing session"; errEl.style.display = "block"; }
      return;
    }

    const payload = {
      p_token: window.currentToken,
      p_pref_shift_clustering: Number(document.getElementById("prefShiftClustering")?.value || 3),
      p_pref_night_appetite: Number(document.getElementById("prefNightAppetite")?.value || 3),
      p_pref_weekend_appetite: Number(document.getElementById("prefWeekendAppetite")?.value || 3),
      p_pref_leave_adjacency: Number(document.getElementById("prefLeaveAdjacency")?.value || 3)
    };

    try {
      const { data, error } = await supabase.rpc("update_my_preferences", payload);
      if (error) throw error;
      // Check if RPC returned an error in the response data
      if (data && data.error) {
        throw new Error(data.error);
      }
      console.log("[USER-PREFS] Save successful", data);
      if (okEl) { okEl.textContent = "Preferences saved."; okEl.style.display = "block"; }
    } catch (e) {
      console.error("[USER-PREFS] Save failed", e);
      if (errEl) {
        errEl.textContent = e?.message || "Save failed";
        errEl.style.display = "block";
      }
    }
  }

  function setLanguage(lang) {
    // Store language preference
    localStorage.setItem('calpeward.language', lang);
    
    // Update button states
    updateLanguageButtons(lang);
    
    // Reload to apply language (if t() function exists)
    if (typeof t === 'function') {
      window.location.reload();
    }
  }

  function updateLanguageButtons(lang) {
    const currentLang = lang || localStorage.getItem('calpeward.language') || 'en';
    const langEn = document.getElementById("userLangEn");
    const langEs = document.getElementById("userLangEs");
    
    if (langEn) {
      if (currentLang === 'en') {
        langEn.classList.add('is-active');
      } else {
        langEn.classList.remove('is-active');
      }
    }
    
    if (langEs) {
      if (currentLang === 'es') {
        langEs.classList.add('is-active');
      } else {
        langEs.classList.remove('is-active');
      }
    }
  }

  // Initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initUserModal);
  } else {
    initUserModal();
  }

  async function loadCalendarTokenStatus() {
    const statusEl = document.getElementById("calendarTokenStatus");
    const linkDisplay = document.getElementById("calendarLinkDisplay");
    const generateBtn = document.getElementById("generateCalendarToken");
    const revokeBtn = document.getElementById("revokeCalendarToken");

    if (!statusEl) return;

    // Simple status - don't query table (blocked by RLS)
    // Users can generate/regenerate as needed
    statusEl.innerHTML = `
      <div style="padding: 10px; background: #f0f9ff; border-radius: 6px; margin-bottom: 12px;">
        <strong>📅 Calendar Subscription</strong><br>
        <small>Generate a secure link to subscribe to your published shifts in any calendar app</small>
      </div>
    `;
    
    if (generateBtn) generateBtn.textContent = "Generate Calendar Link";
    if (revokeBtn) revokeBtn.disabled = false;
    if (linkDisplay) linkDisplay.style.display = "none";
  }

  async function generateCalendarToken() {
    const errEl = document.getElementById("calendarErr");
    const okEl = document.getElementById("calendarOk");
    const linkDisplay = document.getElementById("calendarLinkDisplay");
    const calendarURL = document.getElementById("calendarURL");
    const webcalURL = document.getElementById("webcalURL");

    if (errEl) errEl.style.display = "none";
    if (okEl) okEl.style.display = "none";

    try {
      const supabase = typeof getSupabase === 'function' ? getSupabase() : window.supabaseClient;
      if (!supabase || !window.currentToken) {
        throw new Error("Session not available");
      }

      const { data, error } = await supabase.rpc("generate_calendar_token", {
        p_token: window.currentToken
      });

      if (error) throw error;

      if (!data || !data.success || !data.token) {
        throw new Error("Failed to generate token");
      }

      // Build URLs
      const baseURL = window.SUPABASE_URL || supabase.supabaseUrl;
      const icsURL = `${baseURL}/functions/v1/ics?token=${data.token}`;
      const webcalURLValue = icsURL.replace('https://', 'webcal://');

      // Display URLs
      if (calendarURL) calendarURL.value = icsURL;
      if (webcalURL) webcalURL.value = webcalURLValue;
      if (linkDisplay) linkDisplay.style.display = "block";

      // Show success message
      if (okEl) {
        okEl.textContent = "✅ Calendar link generated! Copy the URL below and add it to your calendar app. Save this link - it won't be shown again.";
        okEl.style.display = "block";
      }

      // Don't reload status - keep the link visible

    } catch (error) {
      console.error("[CALENDAR] Error generating token:", error);
      if (errEl) {
        errEl.textContent = "Failed to generate calendar link: " + error.message;
        errEl.style.display = "block";
      }
    }
  }

  async function revokeCalendarToken() {
    if (!confirm("Revoke calendar subscription? This will disable any apps using the current link.")) {
      return;
    }

    const errEl = document.getElementById("calendarErr");
    const okEl = document.getElementById("calendarOk");
    const linkDisplay = document.getElementById("calendarLinkDisplay");

    if (errEl) errEl.style.display = "none";
    if (okEl) okEl.style.display = "none";

    try {
      const supabase = typeof getSupabase === 'function' ? getSupabase() : window.supabaseClient;
      if (!supabase || !window.currentToken) {
        throw new Error("Session not available");
      }

      const { data, error } = await supabase.rpc("revoke_calendar_token", {
        p_token: window.currentToken
      });

      if (error) throw error;

      // Hide link display
      if (linkDisplay) linkDisplay.style.display = "none";

      // Show success message
      if (okEl) {
        okEl.textContent = "Calendar subscription revoked. Generate a new link when needed.";
        okEl.style.display = "block";
      }

      // Reload status
      await loadCalendarTokenStatus();

    } catch (error) {
      console.error("[CALENDAR] Error revoking token:", error);
      if (errEl) {
        errEl.textContent = "Failed to revoke calendar link: " + error.message;
        errEl.style.display = "block";
      }
    }
  }

  function copyToClipboard(inputId) {
    const input = document.getElementById(inputId);
    if (!input) return;

    input.select();
    input.setSelectionRange(0, 99999); // For mobile

    try {
      document.execCommand('copy');
      
      // Show brief confirmation
      const originalValue = input.value;
      input.value = "✅ Copied!";
      setTimeout(() => {
        input.value = originalValue;
      }, 1500);
    } catch (err) {
      console.error("Failed to copy:", err);
      alert("Failed to copy. Please select and copy manually.");
    }
  }

  // Expose for external use
  window.UserModalModule = {
    closeModal,
    savePIN,
    setLanguage,
    generateCalendarToken,
    revokeCalendarToken
  };

})();

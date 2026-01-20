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

  // Expose for external use
  window.UserModalModule = {
    closeModal,
    savePIN,
    setLanguage
  };

})();

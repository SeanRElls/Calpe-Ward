// admin-leave-management.js
// Handles leave management functionality in admin panel
console.log("[ADMIN-LEAVE-MANAGEMENT] Script loaded");

function initLeaveManagement() {
  console.log("[LEAVE MGMT] Initializing...");

  const leaveUserSelect = document.getElementById("leaveUserSelect");
  const leaveUserDetails = document.getElementById("leaveUserDetails");
  const leaveUserName = document.getElementById("leaveUserName");
  const leaveTotalDays = document.getElementById("leaveTotalDays");
  const leaveTotalHours = document.getElementById("leaveTotalHours");
  const leaveEntriesList = document.getElementById("leaveEntriesList");
  const leaveAddBtn = document.getElementById("leaveAddBtn");
  
  // Tab elements
  const leaveTabIndividual = document.getElementById("leaveTabIndividual");
  const leaveTabAnnual = document.getElementById("leaveTabAnnual");
  const leaveTabIndividualContent = document.getElementById("leaveTabIndividualContent");
  const leaveTabAnnualContent = document.getElementById("leaveTabAnnualContent");

  let currentLeaveUserId = null;
  let currentUserRoleId = null; // Track user role for dialog customization
  let leaveEntries = [];

  // Populate user dropdown when panel is shown (organized by role)
  async function populateUserDropdown() {
    console.log("[LEAVE MGMT] populateUserDropdown called");
    
    leaveUserSelect.innerHTML = '<option value="">-- Loading users... --</option>';
    
    try {
      // Load active users via RPC (includes role_id, avoids RLS policy issues)
      const { data, error } = await window.supabaseClient.rpc("admin_get_active_users", {
        p_token: window.currentToken
      });
      
      if (error) throw error;
      
      const activeUsers = data || [];
      
      if (activeUsers.length === 0) {
        leaveUserSelect.innerHTML = '<option value="">-- No active users found --</option>';
        console.warn("[LEAVE MGMT] No active users found");
        return;
      }

      leaveUserSelect.innerHTML = '<option value="">-- Select a user --</option>';
      
      // Store user data for role lookup on selection
      window.leaveUserRoleMap = {};
      activeUsers.forEach(u => {
        window.leaveUserRoleMap[u.id] = u.role_id;
      });
      
      // Separate into groups: RN/SN (roles 1-2) and NA (role 3)
      const rnSnUsers = activeUsers.filter(u => u.role_id <= 2);
      const naUsers = activeUsers.filter(u => u.role_id === 3);
      
      // Add RN/SN group
      if (rnSnUsers.length > 0) {
        const rnSnGroup = document.createElement('optgroup');
        rnSnGroup.label = '👩‍⚕️ Nurses (RN/SN)';
        rnSnUsers.forEach(user => {
          const option = document.createElement('option');
          option.value = user.id;
          option.textContent = user.name;
          rnSnGroup.appendChild(option);
        });
        leaveUserSelect.appendChild(rnSnGroup);
      }
      
      // Add NA group
      if (naUsers.length > 0) {
        const naGroup = document.createElement('optgroup');
        naGroup.label = '👤 Nursing Assistants (NA)';
        naUsers.forEach(user => {
          const option = document.createElement('option');
          option.value = user.id;
          option.textContent = user.name;
          naGroup.appendChild(option);
        });
        leaveUserSelect.appendChild(naGroup);
      }
      
      console.log("[LEAVE MGMT] Successfully populated dropdown with", activeUsers.length, "users");
    } catch (err) {
      console.error("[LEAVE MGMT] Error loading users:", err);
      leaveUserSelect.innerHTML = '<option value="">-- Error loading users --</option>';
    }
  }

  // Load leave entries for a user
  async function loadLeaveEntries(userId) {
    try {
      const { data, error } = await window.supabaseClient.rpc("admin_get_user_leave_entries", {
        p_token: window.currentToken,
        p_user_id: userId
      });

      if (error) {
        console.error("[LEAVE MGMT] Error loading leave entries:", error);
        return [];
      }

      return data || [];
    } catch (err) {
      console.error("[LEAVE MGMT] Exception loading leave entries:", err);
      return [];
    }
  }

  // Calculate totals
  function calculateTotals(entries) {
    let totalDays = 0;

    entries.forEach(entry => {
      totalDays += entry.leave_days || 0;
    });

    return { totalDays };
  }

  // Render leave entries list
  function renderLeaveEntries() {
    if (leaveEntries.length === 0) {
      leaveEntriesList.innerHTML = '<p style="text-align:center; color:#9ca3af; padding:40px 0;">No leave entries assigned yet.</p>';
      return;
    }

    leaveEntriesList.innerHTML = '';

    // Sort by start_date ascending (earliest first)
    const sortedEntries = [...leaveEntries].sort((a, b) => {
      return new Date(a.start_date) - new Date(b.start_date);
    });

    sortedEntries.forEach(entry => {
      const card = document.createElement("div");
      card.style.cssText = "background:white; border:1px solid #e5e7eb; border-radius:6px; padding:12px; margin-bottom:8px;";
      
      const startDate = new Date(entry.start_date);
      const endDate = new Date(entry.end_date);
      const dateRange = startDate.toLocaleDateString() === endDate.toLocaleDateString()
        ? startDate.toLocaleDateString("en-GB")
        : `${startDate.toLocaleDateString("en-GB")} - ${endDate.toLocaleDateString("en-GB")}`;

      card.innerHTML = `
        <div style="display:flex; justify-content:space-between; align-items:start;">
          <div style="flex:1;">
            <div style="font-weight:600; color:#1f2937; margin-bottom:4px;">${dateRange}</div>
            <div style="font-size:14px; color:#6b7280;">
              <strong>${entry.leave_days}</strong> leave days
            </div>
            ${entry.notes ? `<div style="font-size:12px; color:#9ca3af; margin-top:4px; font-style:italic;">${entry.notes}</div>` : ''}
          </div>
          <div style="display:flex; gap:8px;">
            <button class="btn" style="padding:6px 12px; font-size:13px;" data-action="edit" data-id="${entry.id}">Edit</button>
            <button class="btn" style="padding:6px 12px; font-size:13px; background:#ef4444; color:white;" data-action="delete" data-id="${entry.id}">Delete</button>
          </div>
        </div>
      `;

      // Edit button
      card.querySelector('[data-action="edit"]').addEventListener("click", () => {
        editLeaveEntry(entry);
      });

      // Delete button
      card.querySelector('[data-action="delete"]').addEventListener("click", async () => {
        if (!confirm("Delete this leave entry?")) return;
        await deleteLeaveEntry(entry.id);
      });

      leaveEntriesList.appendChild(card);
    });
  }

  // Show add/edit leave dialog with dual input (hours or days)
  function showLeaveDialog(entry = null) {
    const isEdit = !!entry;
    const isNA = currentUserRoleId === 3; // role_id 3 = Nursing Assistant
    
    const initialDays = entry ? entry.leave_days : (isNA ? 5 : 1);
    
    const dialogHTML = `
      <div style="padding: 24px; background: white; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); max-width: 500px; margin: auto;">
        <h3 style="margin: 0 0 20px 0; color: #1f2937;">${isEdit ? 'Edit' : 'Add'} Leave Entry</h3>
        
        <div style="margin-bottom: 16px;">
          <label style="display: block; margin-bottom: 6px; color: #374151; font-weight: 500; font-size: 0.95em;">
            Start Date
          </label>
          <input type="date" id="leaveDialogStartDate" value="${entry?.start_date || ''}" 
            style="width: 100%; padding: 8px 12px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 1em;" />
        </div>
        
        <div style="margin-bottom: 16px;">
          <label style="display: block; margin-bottom: 6px; color: #374151; font-weight: 500; font-size: 0.95em;">
            End Date
          </label>
          <input type="date" id="leaveDialogEndDate" value="${entry?.end_date || ''}" 
            style="width: 100%; padding: 8px 12px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 1em;" />
        </div>
        
        <div style="margin-bottom: 16px;">
          <label style="display: block; margin-bottom: 6px; color: #374151; font-weight: 500; font-size: 0.95em;">
            📊 Leave Days
          </label>
          <input type="number" id="leaveDialogDays" min="0.5" max="50" step="0.5" value="${initialDays}" 
            style="width: 100%; padding: 8px 12px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 1em;" />
          <p style="margin: 6px 0 0 0; font-size: 0.85em; color: #9ca3af;">
            Enter the number of leave days (e.g., 0.5, 1, 1.5, 4.5)
          </p>
        </div>
        
        <div style="margin-bottom: 20px;">
          <label style="display: block; margin-bottom: 6px; color: #374151; font-weight: 500; font-size: 0.95em;">
            Notes (optional)
          </label>
          <textarea id="leaveDialogNotes" rows="3" placeholder="e.g., Annual leave, sick leave, study leave..."
            style="width: 100%; padding: 8px 12px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 1em; resize: vertical;">${entry?.notes || ''}</textarea>
        </div>
        
        <div style="display: flex; gap: 10px;">
          <button id="leaveDialogSave" style="flex: 1; padding: 10px; background: #3b82f6; color: white; border: none; border-radius: 6px; font-weight: 500; cursor: pointer;">
            ${isEdit ? 'Update' : 'Add'} Leave
          </button>
          <button id="leaveDialogCancel" style="flex: 1; padding: 10px; background: #e5e7eb; color: #374151; border: none; border-radius: 6px; font-weight: 500; cursor: pointer;">
            Cancel
          </button>
        </div>
      </div>
    `;
    
    // Create overlay
    const overlay = document.createElement("div");
    overlay.style.cssText = "position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); display: flex; align-items: center; justify-content: center; z-index: 10000;";
    overlay.innerHTML = dialogHTML;
    
    const daysInput = overlay.querySelector("#leaveDialogDays");
    
    // Save button
    overlay.querySelector("#leaveDialogSave").addEventListener("click", async () => {
      const startDate = overlay.querySelector("#leaveDialogStartDate").value;
      const endDate = overlay.querySelector("#leaveDialogEndDate").value;
      const days = parseFloat(overlay.querySelector("#leaveDialogDays").value) || 0;
      const notes = overlay.querySelector("#leaveDialogNotes").value.trim();
      
      if (!startDate || !endDate) {
        alert("Please enter both start and end dates");
        return;
      }
      
      if (days <= 0) {
        alert("Leave days must be greater than 0");
        return;
      }
      
      overlay.remove();
      
      if (isEdit) {
        await updateLeaveEntry(entry.id, { startDate, endDate, days, notes });
      } else {
        await addLeaveEntry({ startDate, endDate, days, notes });
      }
    });
    
    // Cancel button
    overlay.querySelector("#leaveDialogCancel").addEventListener("click", () => {
      overlay.remove();
    });
    
    document.body.appendChild(overlay);

    const startDateInput = overlay.querySelector("#leaveDialogStartDate");
    const endDateInput = overlay.querySelector("#leaveDialogEndDate");

    const setEndIfSunday = (dateStr) => {
      if (!dateStr || !endDateInput) return;
      const selected = new Date(dateStr);
      if (Number.isNaN(selected.getTime())) return;

      const isSunday = selected.getDay() === 0;
      const shouldAuto = !endDateInput.value || endDateInput.dataset.auto === "true";
      if (isSunday && shouldAuto) {
        const end = new Date(selected);
        end.setDate(end.getDate() + 6);
        const endIso = end.toISOString().split('T')[0];
        endDateInput.value = endIso;
        endDateInput.dataset.auto = "true";
        if (endDatePicker) {
          endDatePicker.setDate(endIso, true);
        }
      }
    };

    endDateInput.addEventListener("change", () => {
      endDateInput.dataset.auto = "false";
    });

    let startDatePicker = null;
    let endDatePicker = null;

    if (window.flatpickr && startDateInput && endDateInput) {
      startDatePicker = window.flatpickr(startDateInput, {
        dateFormat: "Y-m-d",
        allowInput: true,
        locale: { firstDayOfWeek: 0 },
        onChange: (selectedDates, dateStr) => setEndIfSunday(dateStr)
      });

      endDatePicker = window.flatpickr(endDateInput, {
        dateFormat: "Y-m-d",
        allowInput: true,
        locale: { firstDayOfWeek: 0 }
      });
    } else if (startDateInput) {
      startDateInput.addEventListener("change", (e) => setEndIfSunday(e.target.value));
    }
    
    // Don't auto-focus to prevent calendar from auto-opening
  }

  // Check for bank holidays in a date range
  async function checkBankHolidays(startDate, endDate) {
    try {
      // Get all bank holidays for the year and filter client-side
      const { data, error } = await window.supabaseClient.rpc('rpc_get_all_bank_holidays', {
        p_start_year: new Date(startDate).getFullYear(),
        p_end_year: new Date(endDate).getFullYear()
      });
      
      if (error) throw error;
      
      // Filter to only holidays within the date range
      const holidays = (data || []).filter(h => {
        const hDate = new Date(h.holiday_date).toISOString().split('T')[0];
        return hDate >= startDate && hDate <= endDate;
      });
      
      return holidays;
    } catch (err) {
      console.warn("[LEAVE MGMT] Error checking bank holidays:", err);
      return [];
    }
  }

  // Show confirmation dialog for leave with bank holidays
  function showBankHolidayConfirmation(startDate, endDate, holidays, onConfirm, onAmend, onCancel) {
    const dialog = document.createElement('div');
    dialog.style.cssText = `
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      background: rgba(0,0,0,0.5);
      display: flex;
      align-items: center;
      justify-content: center;
      z-index: 10000;
    `;
    
    const content = document.createElement('div');
    content.style.cssText = `
      background: white;
      border-radius: 8px;
      padding: 24px;
      max-width: 500px;
      box-shadow: 0 4px 20px rgba(0,0,0,0.3);
      font-family: Manrope, sans-serif;
    `;
    
    const title = document.createElement('h3');
    title.textContent = '⚠️ Bank Holidays Detected';
    title.style.cssText = 'margin: 0 0 16px 0; color: #d97706; font-size: 18px;';
    
    const message = document.createElement('p');
    message.textContent = `There ${holidays.length === 1 ? 'is 1 bank holiday' : 'are ' + holidays.length + ' bank holidays'} in this period:`;
    message.style.cssText = 'margin: 0 0 12px 0; color: #333;';
    
    const list = document.createElement('ul');
    list.style.cssText = 'margin: 12px 0 16px 20px; color: #666; font-size: 14px;';
    holidays.forEach(h => {
      const li = document.createElement('li');
      li.textContent = `${h.holiday_date} - ${h.name}`;
      list.appendChild(li);
    });
    
    const warning = document.createElement('p');
    warning.textContent = `You need to reduce their leave allocation by ${holidays.length} leave day${holidays.length > 1 ? 's' : ''}.`;
    warning.style.cssText = 'margin: 16px 0 20px 0; padding: 12px; background: #fef3c7; border-left: 4px solid #d97706; color: #92400e; font-size: 14px;';
    
    const buttons = document.createElement('div');
    buttons.style.cssText = 'display: flex; gap: 12px; justify-content: flex-end;';
    
    const cancelBtn = document.createElement('button');
    cancelBtn.textContent = 'Cancel';
    cancelBtn.style.cssText = `
      padding: 10px 20px;
      border: 1px solid #ddd;
      border-radius: 4px;
      background: #f3f4f6;
      cursor: pointer;
      font-weight: 500;
      color: #333;
    `;
    cancelBtn.onclick = () => {
      dialog.remove();
      if (onCancel) onCancel();
    };
    
    const amendBtn = document.createElement('button');
    amendBtn.textContent = 'Amend';
    amendBtn.style.cssText = `
      padding: 10px 20px;
      border: 1px solid #3b82f6;
      border-radius: 4px;
      background: transparent;
      cursor: pointer;
      font-weight: 500;
      color: #3b82f6;
    `;
    amendBtn.onclick = () => {
      dialog.remove();
      if (onAmend) onAmend();
    };
    
    const proceedBtn = document.createElement('button');
    proceedBtn.textContent = 'Proceed';
    proceedBtn.style.cssText = `
      padding: 10px 20px;
      border: none;
      border-radius: 4px;
      background: #3b82f6;
      cursor: pointer;
      font-weight: 500;
      color: white;
    `;
    proceedBtn.onclick = () => {
      dialog.remove();
      if (onConfirm) onConfirm();
    };
    
    buttons.appendChild(cancelBtn);
    buttons.appendChild(amendBtn);
    buttons.appendChild(proceedBtn);
    
    content.appendChild(title);
    content.appendChild(message);
    content.appendChild(list);
    content.appendChild(warning);
    content.appendChild(buttons);
    
    dialog.appendChild(content);
    document.body.appendChild(dialog);
  }

  // Check if current period is published
  // Check if the leave dates fall within a published period
  async function isPeriodPublished(startDate, endDate) {
    try {
      // Use RPC to check if leave dates overlap with any published period
      const { data, error } = await window.supabaseClient.rpc(
        'admin_check_leave_in_published_period',
        {
          p_token: window.currentToken,
          p_start_date: startDate,
          p_end_date: endDate
        }
      );

      if (error) {
        console.warn("[LEAVE MGMT] Error checking period status:", error);
        return false;
      }

      if (data) {
        console.log("[LEAVE MGMT] Leave dates fall within published period");
        return true;
      }

      console.log("[LEAVE MGMT] Leave dates do not fall within any published period");
      return false;
    } catch (err) {
      console.warn("[LEAVE MGMT] Error checking period status:", err);
      return false;
    }
  }

  // Check for existing shifts in date range
  async function checkExistingShifts(startDate, endDate) {
    try {
      const { data, error } = await window.supabaseClient.rpc("admin_get_shifts_to_remove", {
        p_token: window.currentToken,
        p_user_id: currentLeaveUserId,
        p_start_date: startDate,
        p_end_date: endDate
      });

      if (error) throw error;

      return data || [];
    } catch (err) {
      console.warn("[LEAVE MGMT] Error checking existing shifts:", err);
      return [];
    }
  }

  // Show confirmation dialog for shifts that will be removed
  function showShiftsConfirmation(startDate, endDate, shifts, onConfirm, onCancel) {
    const dialog = document.createElement('div');
    dialog.style.cssText = `
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      background: rgba(0,0,0,0.5);
      display: flex;
      align-items: center;
      justify-content: center;
      z-index: 10000;
    `;
    
    const content = document.createElement('div');
    content.style.cssText = `
      background: white;
      border-radius: 8px;
      padding: 24px;
      max-width: 500px;
      box-shadow: 0 4px 20px rgba(0,0,0,0.3);
      font-family: Manrope, sans-serif;
    `;
    
    const title = document.createElement('h3');
    title.textContent = '⚠️ Existing Shifts Will Be Removed';
    title.style.cssText = 'margin: 0 0 16px 0; color: #d97706; font-size: 18px;';
    
    const message = document.createElement('p');
    message.textContent = `This period is published. Assigning leave will remove ${shifts.length} existing shift${shifts.length !== 1 ? 's' : ''}:`;
    message.style.cssText = 'margin: 0 0 12px 0; color: #333;';
    
    const list = document.createElement('ul');
    list.style.cssText = 'margin: 12px 0 16px 20px; color: #666; font-size: 14px; max-height: 200px; overflow-y: auto;';
    shifts.forEach(shift => {
      const li = document.createElement('li');
      const dateStr = new Date(shift.date).toLocaleDateString('en-GB', { weekday: 'short', month: 'short', day: 'numeric' });
      li.textContent = `${dateStr} - ${shift.shift_label || shift.shift_code}`;
      list.appendChild(li);
    });
    
    const warning = document.createElement('p');
    warning.textContent = 'A history record will be created for each removed shift with reason "Leave assigned".';
    warning.style.cssText = 'margin: 16px 0 20px 0; padding: 12px; background: #fef3c7; border-left: 4px solid #d97706; color: #92400e; font-size: 14px;';
    
    const buttons = document.createElement('div');
    buttons.style.cssText = 'display: flex; gap: 12px; justify-content: flex-end;';
    
    const cancelBtn = document.createElement('button');
    cancelBtn.textContent = 'Cancel';
    cancelBtn.style.cssText = `
      padding: 10px 20px;
      border: 1px solid #ddd;
      border-radius: 4px;
      background: #f3f4f6;
      cursor: pointer;
      font-weight: 500;
      color: #333;
    `;
    cancelBtn.onclick = () => {
      dialog.remove();
      if (onCancel) onCancel();
    };
    
    const confirmBtn = document.createElement('button');
    confirmBtn.textContent = 'Continue';
    confirmBtn.style.cssText = `
      padding: 10px 20px;
      border: none;
      border-radius: 4px;
      background: #d97706;
      cursor: pointer;
      font-weight: 500;
      color: white;
    `;
    confirmBtn.onclick = () => {
      dialog.remove();
      if (onConfirm) onConfirm();
    };
    
    buttons.appendChild(cancelBtn);
    buttons.appendChild(confirmBtn);
    
    content.appendChild(title);
    content.appendChild(message);
    content.appendChild(list);
    content.appendChild(warning);
    content.appendChild(buttons);
    
    dialog.appendChild(content);
    document.body.appendChild(dialog);
  }

  // Add new leave entry
  async function addLeaveEntry({ startDate, endDate, days, notes }) {
    try {
      console.log("[LEAVE MGMT] addLeaveEntry called with:", {
        startDate: startDate,
        endDate: endDate,
        days: days,
        notes: notes
      });
      
      // First, check for existing shifts to be removed
      const existingShifts = await checkExistingShifts(startDate, endDate);
      
      if (existingShifts.length > 0) {
        // Get current period status for these dates
        const isPublished = await isPeriodPublished(startDate, endDate);
        
        if (isPublished) {
          // Show confirmation dialog for shifts
          return new Promise((resolve) => {
            showShiftsConfirmation(
              startDate,
              endDate,
              existingShifts,
              async () => {
                // User confirmed - proceed to check holidays
                await proceedWithLeaveEntry(startDate, endDate, days, notes);
                resolve();
              },
              () => {
                // User cancelled
                resolve();
              }
            );
          });
        } else {
          // Draft period - proceed silently
          await proceedWithLeaveEntry(startDate, endDate, days, notes);
        }
      } else {
        // No shifts - proceed to holiday check
        await proceedWithLeaveEntry(startDate, endDate, days, notes);
      }
    } catch (err) {
      console.error("[LEAVE MGMT] Error in addLeaveEntry:", err);
      alert("Failed to process leave entry: " + err.message);
    }
  }

  // Common logic for adding leave after all checks
  async function proceedWithLeaveEntry(startDate, endDate, days, notes) {
    // Check for bank holidays
    const holidays = await checkBankHolidays(startDate, endDate);
    
    if (holidays.length > 0) {
      // Show confirmation dialog
      return new Promise((resolve) => {
        showBankHolidayConfirmation(
          startDate,
          endDate,
          holidays,
          async () => {
            // User clicked Proceed
            await performAddLeaveEntry(startDate, endDate, days, notes);
            resolve();
          },
          () => {
            // User clicked Amend - just close the dialog, form stays open
            resolve();
          },
          () => {
            // User clicked Cancel
            resolve();
          }
        );
      });
    } else {
      // No holidays, proceed directly
      await performAddLeaveEntry(startDate, endDate, days, notes);
    }
  }

  // Perform the actual leave entry insertion
  async function performAddLeaveEntry(startDate, endDate, days, notes) {
    try {
      // Single RPC call that does both: insert leave entry AND create assignments
      const { data, error } = await window.supabaseClient.rpc("admin_add_user_leave_entry", {
        p_token: window.currentToken,
        p_user_id: currentLeaveUserId,
        p_start_date: startDate,
        p_end_date: endDate,
        p_leave_days: days,
        p_leave_hours: null,
        p_notes: notes || null
      });

      if (error) throw error;

      console.log("[LEAVE MGMT] Leave entry added and assignments created:", data);
      
      // Show success message with assignment details
      const result = Array.isArray(data) ? data[0] : data;
      const message = result?.message || "Leave entry added";
      
      alert("✅ " + message);
      
      // Trigger rota reload if a period is currently active
      if (window.loadPeriod && window.currentPeriod?.id) {
        console.log("[LEAVE MGMT] Reloading current period to show leave assignments");
        await window.loadPeriod(window.currentPeriod.id);
      }
      
      await refreshLeaveData();
    } catch (err) {
      console.error("[LEAVE MGMT] Error adding leave entry:", err);
      alert("Failed to add leave entry: " + err.message);
    }
  }

  // Update leave entry
  async function updateLeaveEntry(id, { startDate, endDate, days, notes }) {
    try {
      // First, check for existing shifts to be removed
      const existingShifts = await checkExistingShifts(startDate, endDate);
      
      if (existingShifts.length > 0) {
        // Get current period status for these dates
        const isPublished = await isPeriodPublished(startDate, endDate);
        
        if (isPublished) {
          // Show confirmation dialog for shifts
          return new Promise((resolve) => {
            showShiftsConfirmation(
              startDate,
              endDate,
              existingShifts,
              async () => {
                // User confirmed - proceed to check holidays
                await proceedWithLeaveUpdate(id, startDate, endDate, days, notes);
                resolve();
              },
              () => {
                // User cancelled
                resolve();
              }
            );
          });
        } else {
          // Draft period - proceed silently
          await proceedWithLeaveUpdate(id, startDate, endDate, days, notes);
        }
      } else {
        // No shifts - proceed to holiday check
        await proceedWithLeaveUpdate(id, startDate, endDate, days, notes);
      }
    } catch (err) {
      console.error("[LEAVE MGMT] Error in updateLeaveEntry:", err);
      alert("Failed to process leave update: " + err.message);
    }
  }

  // Common logic for updating leave after all checks
  async function proceedWithLeaveUpdate(id, startDate, endDate, days, notes) {
    // Check for bank holidays
    const holidays = await checkBankHolidays(startDate, endDate);
    
    if (holidays.length > 0) {
      // Show confirmation dialog
      return new Promise((resolve) => {
        showBankHolidayConfirmation(
          startDate,
          endDate,
          holidays,
          async () => {
            // User clicked Proceed
            await performUpdateLeaveEntry(id, startDate, endDate, days, notes);
            resolve();
          },
          () => {
            // User clicked Amend - just close the dialog, form stays open
            resolve();
          },
          () => {
            // User clicked Cancel
            resolve();
          }
        );
      });
    } else {
      // No holidays, proceed directly
      await performUpdateLeaveEntry(id, startDate, endDate, days, notes);
    }
  }

  // Perform the actual leave entry update
  async function performUpdateLeaveEntry(id, startDate, endDate, days, notes) {
    try {
      const { data, error } = await window.supabaseClient.rpc("admin_update_user_leave_entry", {
        p_token: window.currentToken,
        p_leave_id: id,
        p_user_id: currentLeaveUserId,
        p_start_date: startDate,
        p_end_date: endDate,
        p_leave_days: days,
        p_leave_hours: null,
        p_notes: notes || null
      });

      if (error) throw error;

      console.log("[LEAVE MGMT] Leave entry updated", data);
      
      // Show success message
      const result = Array.isArray(data) ? data[0] : data;
      const message = result?.message || "Leave entry updated";
      
      alert("✅ " + message);
      
      // Trigger rota reload if a period is currently active
      if (window.loadPeriod && window.currentPeriod?.id) {
        console.log("[LEAVE MGMT] Reloading current period to show updated leave assignments");
        await window.loadPeriod(window.currentPeriod.id);
      }
      
      await refreshLeaveData();
    } catch (err) {
      console.error("[LEAVE MGMT] Error updating leave entry:", err);
      alert("Failed to update leave entry: " + err.message);
    }
  }

  // Delete leave entry
  async function deleteLeaveEntry(id) {
    try {
      // First, fetch the leave entry to get its dates
      const leaveEntry = leaveEntries.find(e => e.id === id);
      if (!leaveEntry) {
        alert("Leave entry not found");
        return;
      }

      // Check if this leave falls within a published period
      const isPublished = await isPeriodPublished(leaveEntry.start_date, leaveEntry.end_date);

      // Call RPC with the published status flag
      const { data, error } = await window.supabaseClient.rpc("admin_delete_user_leave_entry", {
        p_token: window.currentToken,
        p_leave_id: id,
        p_is_published_period: isPublished
      });

      if (error) throw error;

      console.log("[LEAVE MGMT] Leave entry deleted:", data);
      
      // Show success message with assignment count
      if (data && data.length > 0) {
        alert(data[0].message || "Leave entry deleted");
      }
      
      // Reload the rota if available
      if (typeof window.loadPeriod === 'function') {
        window.loadPeriod();
      }
      
      await refreshLeaveData();
    } catch (err) {
      console.error("[LEAVE MGMT] Error deleting leave entry:", err);
      alert("Failed to delete leave entry: " + err.message);
    }
  }

  // Edit leave entry
  function editLeaveEntry(entry) {
    showLeaveDialog(entry);
  }

  // Refresh leave data after changes
  async function refreshLeaveData() {
    if (!currentLeaveUserId) return;
    
    leaveEntries = await loadLeaveEntries(currentLeaveUserId);
    const { totalDays } = calculateTotals(leaveEntries);
    
    leaveTotalDays.textContent = totalDays.toFixed(1);
    
    renderLeaveEntries();
  }

  // User selection change
  leaveUserSelect.addEventListener("change", async (e) => {
    const userId = String(e.target.value); // Ensure it's a string
    
    if (!userId) {
      leaveUserDetails.style.display = "none";
      currentLeaveUserId = null;
      currentUserRoleId = null;
      return;
    }
    
    currentLeaveUserId = userId;
    currentUserRoleId = window.leaveUserRoleMap?.[userId] || null; // Capture role ID
    
    // Get user name from the selected option text
    const userName = leaveUserSelect.options[leaveUserSelect.selectedIndex].text;
    
    leaveUserName.textContent = userName;
    leaveUserDetails.style.display = "block";
    
    await refreshLeaveData();
  });

  // Add leave button
  leaveAddBtn.addEventListener("click", () => {
    showLeaveDialog();
  });

  // Populate dropdown when leave-management panel is shown
  const navLinks = document.querySelectorAll('.nav a[data-panel]');
  navLinks.forEach(link => {
    if (link.getAttribute('data-panel') === 'leave-management') {
      link.addEventListener('click', () => {
        // Delay to ensure panel is visible and users are loaded
        setTimeout(() => {
          console.log("[LEAVE MGMT] Panel clicked, populating dropdown");
          populateUserDropdown();
        }, 200);
      });
    }
  });
  
  // Don't populate on initial load - wait for user to click the panel
  console.log("[LEAVE MGMT] Initialization complete");

  // Tab switching handlers
  function setLeaveTab(active) {
    const isIndividual = active === 'individual';
    leaveTabIndividualContent.style.display = isIndividual ? 'block' : 'none';
    leaveTabAnnualContent.style.display = isIndividual ? 'none' : 'block';

    leaveTabIndividual.classList.toggle('active', isIndividual);
    leaveTabAnnual.classList.toggle('active', !isIndividual);

    // Match inline styles from HTML
    leaveTabIndividual.style.color = isIndividual ? '#3b82f6' : '#6b7280';
    leaveTabIndividual.style.borderBottom = isIndividual ? '2px solid #3b82f6' : '2px solid transparent';

    leaveTabAnnual.style.color = !isIndividual ? '#3b82f6' : '#6b7280';
    leaveTabAnnual.style.borderBottom = !isIndividual ? '2px solid #3b82f6' : '2px solid transparent';
  }

  leaveTabIndividual.addEventListener('click', () => {
    setLeaveTab('individual');
  });

  leaveTabAnnual.addEventListener('click', () => {
    setLeaveTab('annual');
    // Load annual view when tab is clicked
    loadAnnualView();
  });
}

// Load annual leave view showing all weeks in each month (Jan 1 - Dec 31)
async function loadAnnualView() {
  const container = document.getElementById('leaveAnnualView');
  if (!container) return;

  try {
    // Show loading state
    container.innerHTML = '<div style="text-align:center; padding: 20px;">Loading annual leave schedule...</div>';

    // Get current year
    const currentYear = new Date().getFullYear();
    const yearStart = new Date(currentYear, 0, 1);
    const yearEnd = new Date(currentYear, 11, 31);

    // Fetch users once for role/name mapping (via RPC to avoid RLS issues)
    const { data: users, error: usersError } = await window.supabaseClient
      .rpc('admin_get_active_users', {
        p_token: window.currentToken
      });

    if (usersError) {
      console.error("[LEAVE MGMT] Error fetching users:", usersError);
      container.innerHTML = '<div style="color: red; padding: 12px;">Error loading user data</div>';
      return;
    }

    const usersById = {};
    (users || []).forEach(u => { usersById[u.id] = u; });

    // Fetch leave entries per user via RPC to avoid RLS on user_leave_entries
    const leaveEntries = [];
    const userList = users || [];
    await Promise.all(userList.map(async (u) => {
      const { data: entries, error: entriesError } = await window.supabaseClient
        .rpc('admin_get_user_leave_entries', {
          p_token: window.currentToken,
          p_user_id: u.id
        });

      if (entriesError) {
        console.warn('[LEAVE MGMT] Leave entries fetch failed for user', u.id, entriesError);
        return;
      }

      (entries || []).forEach(entry => {
        const start = new Date(entry.start_date);
        const end = new Date(entry.end_date);
        if (start <= yearEnd && end >= yearStart) {
          leaveEntries.push({ ...entry, user_id: u.id });
        }
      });
    }));

    // Build month-only weeks (Sundays within each month)
    function getMonthWeeks(year, monthIndex) {
      const monthWeeks = [];
      let d = new Date(year, monthIndex, 1);
      while (d.getDay() !== 0) {
        d.setDate(d.getDate() + 1);
      }
      while (d.getMonth() === monthIndex && d <= yearEnd) {
        const start = new Date(d);
        const end = new Date(d);
        end.setDate(end.getDate() + 6);
        monthWeeks.push({ start, end });
        d.setDate(d.getDate() + 7);
      }
      return monthWeeks;
    }

    // Build month tables
    container.innerHTML = '';
    const fixedColumns = 5;

    for (let monthIndex = 0; monthIndex < 12; monthIndex++) {
      const monthWeeks = getMonthWeeks(currentYear, monthIndex);
      if (!monthWeeks.length) continue;

      const monthName = new Date(currentYear, monthIndex, 1).toLocaleDateString('en-GB', { month: 'long', year: 'numeric' });

      const table = document.createElement('table');
      table.style.width = '100%';
      table.style.borderCollapse = 'collapse';
      table.style.fontSize = '12px';
      table.style.marginBottom = '10px';
      table.style.tableLayout = 'fixed';

      // Header row for month with week dates
      const thead = document.createElement('thead');
      const headerRow = document.createElement('tr');
      headerRow.style.background = '#2c5aa0';
      headerRow.style.color = 'white';
      headerRow.innerHTML = `<th style="padding:8px 12px; text-align:left; font-weight:700; width:140px; border:1px solid #2c5aa0; font-size:12px;">${monthName}</th>`;

      const paddedWeeks = [...monthWeeks];
      while (paddedWeeks.length < fixedColumns) paddedWeeks.push(null);

      paddedWeeks.forEach(week => {
        if (!week) {
          headerRow.innerHTML += `<th style="padding:8px 6px; text-align:center; border:1px solid #2c5aa0; background:#2c5aa0; color:white; font-weight:600; min-width:110px; font-size:11px;">&nbsp;</th>`;
          return;
        }
        const dayNum = week.start.getDate();
        const monthNum = week.start.getMonth() + 1;
        const yearNum = week.start.getFullYear().toString().slice(-2);
        headerRow.innerHTML += `<th style="padding:8px 6px; text-align:center; border:1px solid #2c5aa0; background:#2c5aa0; color:white; font-weight:700; min-width:110px; font-size:11px;">${dayNum}.${String(monthNum).padStart(2, '0')}.${yearNum}</th>`;
      });
      thead.appendChild(headerRow);
      table.appendChild(thead);

      const tbody = document.createElement('tbody');

      // Nurse row
      const nurseRow = document.createElement('tr');
      nurseRow.style.background = '#a8d5f7';
      nurseRow.innerHTML = `<td style="padding:10px 12px; font-weight:700; border:1px solid #e5e7eb; background:#a8d5f7; color:#0f172a;">Nurse</td>`;
      paddedWeeks.forEach(week => {
        const cellContent = getStaffForWeek(week, leaveEntries, usersById, 'nurse');
        nurseRow.innerHTML += `<td style="padding:10px 6px; border:1px solid #e5e7eb; text-align:left; font-size:12px; min-width:110px; vertical-align:top;">${cellContent}</td>`;
      });
      tbody.appendChild(nurseRow);

      // Nursing Assistant row
      const naRow = document.createElement('tr');
      naRow.style.background = '#a8d5f7';
      naRow.innerHTML = `<td style="padding:10px 12px; font-weight:700; border:1px solid #e5e7eb; background:#a8d5f7; color:#0f172a;">Nursing Assistant</td>`;
      paddedWeeks.forEach(week => {
        const cellContent = getStaffForWeek(week, leaveEntries, usersById, 'na');
        naRow.innerHTML += `<td style="padding:10px 6px; border:1px solid #e5e7eb; text-align:left; font-size:12px; min-width:110px; vertical-align:top;">${cellContent}</td>`;
      });
      tbody.appendChild(naRow);

      table.appendChild(tbody);
      container.appendChild(table);
    }

    console.log("[LEAVE MGMT] Annual view loaded successfully");

  } catch (error) {
    console.error("[LEAVE MGMT] Unexpected error loading annual view:", error);
    container.innerHTML = '<div style="color: red; padding: 12px;">Unexpected error: ' + error.message + '</div>';
  }
}

// Helper function to get staff names for a week and role type
function getStaffForWeek(week, leaveEntries, usersById, roleType) {
  if (!week) return '';
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  // Find leave entries that overlap with this week
  const weekLeave = leaveEntries.filter(entry => {
    const entryStart = new Date(entry.start_date);
    const entryEnd = new Date(entry.end_date);
    return entryStart <= week.end && entryEnd >= week.start;
  });

  const staffStatus = new Map();

  for (const leave of weekLeave) {
    const user = usersById[leave.user_id];
    if (user) {
      const isNurse = user.role_id === 1 || user.role_id === 2;
      const isNA = user.role_id === 3;

      // Add to appropriate list based on roleType filter
      if ((roleType === 'nurse' && isNurse) || (roleType === 'na' && isNA)) {
        const entryEnd = new Date(leave.end_date);
        entryEnd.setHours(0, 0, 0, 0);
        const isPast = entryEnd < today;
        const existing = staffStatus.get(user.name);
        if (!existing) {
          staffStatus.set(user.name, { isPast });
        } else if (!isPast) {
          staffStatus.set(user.name, { isPast: false });
        }
      }
    }
  }

  if (staffStatus.size === 0) return '';
  return Array.from(staffStatus.entries())
    .map(([name, info]) => {
      const tick = info.isPast ? '✅ ' : '';
      return `<div style="font-weight:700; color:#0f172a; background:#e0f2fe; border:1px solid #bae6fd; border-radius:4px; padding:3px 6px; margin:2px 0;">${tick}${name}</div>`;
    })
    .join('');
}

// Initialize when DOM is ready
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initLeaveManagement);
} else {
  initLeaveManagement();
}

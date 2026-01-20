// shift-editor.js
// Handles all rota editing UI and logic (draft, published, overrides)
// Author: Calpe Ward Dev Team
// Last updated: Jan 2026

// ========== STATE ==========
const ROLE_TO_STAFF_GROUP_EDIT = {
  1: "CN",
  2: "SN",
  3: "NA"
};

let isEditingUnlocked = false;
let draftShifts = [];
let editPermissionKey = "rota.edit_draft";
let editContextLabel = "draft rota";
let editMode = "draft"; // "draft" | "published"
let lockedLabel = "🔒 Locked";
let unlockedLabel = "🔓 Editing";
let shiftFilterFn = () => true; // defaults to all shifts
let pickerContext = null;
let pickerKeyHandler = null;
let pickerKeyBuffer = "";
let pickerKeyTimer = null;
let gridKeyHandler = null;
let focusedCell = null;
let lastFocusKey = null;
let gridCodeBuffer = "";
let gridCodeTimer = null;
let selectedShiftId = null; // Track selected shift in picker

// ========== INIT ==========
function initDraftEditing({
  onUnlock,
  onLock,
  onSave,
  onClear,
  onPublishedCellClick,
  getCurrentUser,
  getCurrentPeriod,
  getAllUsers,
  getDraftShifts,
  getAssignment,
  getOverride,
  refreshGrid
}) {
  // Wrap callbacks to restore focus immediately after operations
  const restoreFocusAfterOp = () => {
    if (!lastFocusKey) return;
    requestAnimationFrame(() => {
      const cells = Array.from(document.querySelectorAll("#rota td.cell"));
      const cell = cells.find(c => `${c.dataset.userId}_${c.dataset.date}` === lastFocusKey);
      if (cell) {
        focusedCell = cell;
        cell.classList.add("focused");
      }
    });
  };

  const wrappedOnSave = async (userId, date, shiftId, overrideData) => {
    await onSave(userId, date, shiftId, overrideData);
    restoreFocusAfterOp();
  };

  const wrappedOnClear = async (userId, date) => {
    await onClear(userId, date);
    restoreFocusAfterOp();
  };
  // Bind unlock toggle
  const btn = document.getElementById("toggleEditingBtn");
  if (btn) {
    btn.addEventListener("click", () => {
      if (!window.PermissionsModule?.hasPermission(editPermissionKey)) {
        alert("You don't have permission to edit this rota.");
        return;
      }
      if (!isEditingUnlocked) {
        if (!confirm(`Editing enabled. Changes affect the ${editContextLabel}.`)) return;
        isEditingUnlocked = true;
        btn.textContent = unlockedLabel;
        btn.classList.add("primary");
        if (onUnlock) onUnlock();
      } else {
        isEditingUnlocked = false;
        btn.textContent = lockedLabel;
        btn.classList.remove("primary");
        if (onLock) onLock();
      }
      // Update cell editability
      document.querySelectorAll("#rota td.cell").forEach(td => {
        td.classList.toggle("editable", isEditingUnlocked);
      });
    });
  }

  // Picker modal events
  const closeBtn = document.getElementById("shiftPickerClose");
  if (closeBtn) closeBtn.addEventListener("click", closeShiftPicker);
  const clearBtn = document.getElementById("shiftPickerClear");
  if (clearBtn) clearBtn.addEventListener("click", clearShiftAssignment);
  const saveBtn = document.getElementById("shiftPickerSave");
  if (saveBtn) saveBtn.addEventListener("click", saveShiftAssignment);

  // Cell click handler (delegated)
  const rotaTable = document.getElementById("rota");
  if (!rotaTable) return;

  rotaTable.addEventListener("click", e => {
    const td = e.target.closest("td.cell");
    if (!td) return;
    if (e.button === 2) return; // ignore right-clicks to allow context menu

    // Published flow: never open picker directly; route via host callback
    if (editMode === "published") {
      if (typeof onPublishedCellClick === "function") {
        onPublishedCellClick({ td, userId: td.dataset.userId, date: td.dataset.date, assignment: getAssignment(td.dataset.userId, td.dataset.date) });
      }
      return;
    }

    if (!isEditingUnlocked || !window.PermissionsModule?.hasPermission(editPermissionKey)) return;
    setFocusedCell(td);
    const userId = td.dataset.userId;
    const date = td.dataset.date;
    const assignment = getAssignment(userId, date);
    openShiftPicker(userId, date, assignment);
  });

  rotaTable.addEventListener("contextmenu", e => {
    const td = e.target.closest("td.cell");
    if (!td) return;
    if (editMode === "published" && typeof onPublishedCellClick === "function") {
      // Let admins use the custom context menu; otherwise keep the published click handling
      if (window.currentUser?.is_admin) return; // allow context menu to handle
      e.preventDefault();
      onPublishedCellClick({ td, userId: td.dataset.userId, date: td.dataset.date, assignment: getAssignment(td.dataset.userId, td.dataset.date) });
    }
  });

  // Global keyboard navigation for desktop (grid-level)
  detachGridKeys();
  gridKeyHandler = (e) => {
    // Ignore when picker is open or editing is locked
    const pickerVisible = document.getElementById("shiftPickerBackdrop")?.getAttribute("aria-hidden") === "false";
    if (editMode === "published") return; // no keyboard editing in published
    if (!isEditingUnlocked || pickerVisible || !window.PermissionsModule?.hasPermission(editPermissionKey)) return;

    // Skip when typing in form fields
    const target = e.target;
    const skipTags = ["INPUT", "TEXTAREA", "SELECT", "BUTTON"]; // buttons still handled via click
    if (skipTags.includes(target.tagName) || target.isContentEditable) return;

    const cells = Array.from(document.querySelectorAll("#rota td.cell"));
    if (!cells.length) return;

    // Restore focus to the last known cell if the DOM re-rendered
    if ((!focusedCell || !document.body.contains(focusedCell)) && lastFocusKey) {
      focusedCell = cells.find(c => `${c.dataset.userId}_${c.dataset.date}` === lastFocusKey) || null;
    }

    // If no focus yet, start at the first cell
    if (!focusedCell) {
      setFocusedCell(cells[0]);
    }

    const current = focusedCell;
    const userId = current?.dataset.userId;
    const date = current?.dataset.date;

    const moveFocus = (next) => {
      if (next) {
        setFocusedCell(next);
        next.scrollIntoView({ block: "nearest", inline: "nearest" });
      }
    };

    // Movement helpers by user/date grouping
    const rowCells = userId ? cells.filter(c => c.dataset.userId === userId) : cells;
    const colCells = date ? cells.filter(c => c.dataset.date === date) : cells;
    const idxRow = rowCells.indexOf(current);
    const idxCol = colCells.indexOf(current);

    switch (e.key) {
      case "ArrowRight":
        e.preventDefault();
        if (idxRow >= 0 && idxRow < rowCells.length - 1) moveFocus(rowCells[idxRow + 1]);
        break;
      case "ArrowLeft":
        e.preventDefault();
        if (idxRow > 0) moveFocus(rowCells[idxRow - 1]);
        break;
      case "ArrowDown":
        e.preventDefault();
        if (idxCol >= 0 && idxCol < colCells.length - 1) moveFocus(colCells[idxCol + 1]);
        break;
      case "ArrowUp":
        e.preventDefault();
        if (idxCol > 0) moveFocus(colCells[idxCol - 1]);
        break;
      case "Enter":
      case " ": // Space
        e.preventDefault();
        if (!current) return;
        const assignment = getAssignment(userId, date);
        openShiftPicker(userId, date, assignment);
        break;
      case "Backspace":
      case "Delete":
        if (!current) return;
        e.preventDefault();
        wrappedOnClear(userId, date);
        break;
      default: {
        // Direct code entry on grid (no Enter needed). Buffer per grid.
        const allowed = /^[a-zA-Z0-9*\-]$/;
        if (!allowed.test(e.key)) break;
        e.preventDefault();

        const shifts = (getDraftShifts() || []).filter(shiftFilterFn);
        const codeList = shifts.map(s => (s.code || "").toUpperCase());

        const applyResolution = (resolution) => {
          if (!resolution || resolution.ambiguous) return false;
          wrappedOnSave(userId, date, resolution.id);
          gridCodeBuffer = "";
          return true;
        };

        const tryResolve = (force) => {
          if (!gridCodeBuffer) return false;

          // Special O cycle: O (ID 7) ↔ O* (ID 23)
          if (gridCodeBuffer === "O") {
            const currentAssignment = getAssignment(userId, date);
            const normalO = shifts.find(s => s.id === 7);
            const redO = shifts.find(s => s.id === 23);
            
            if (currentAssignment) {
              const currentShiftId = currentAssignment.shift_id;
              
              if (currentShiftId === 7 && redO) {
                // O is assigned, cycle to O*
                applyResolution(redO);
                return true;
              } else if (currentShiftId === 23 && normalO) {
                // O* is assigned, cycle back to O
                applyResolution(normalO);
                return true;
              }
            }
            
            // No current assignment or different shift - apply normal O first
            if (normalO) {
              applyResolution(normalO);
              return true;
            }
          }

          const resolution = resolveShiftByCode(gridCodeBuffer, userId, shifts);
          if (!resolution) return false;
          if (resolution.ambiguous) {
            if (force) {
              const assignmentAmb = getAssignment(userId, date);
              openShiftPicker(userId, date, assignmentAmb);
            }
            return false;
          }
          return applyResolution(resolution);
        };

        // Append to buffer and schedule resolution
        gridCodeBuffer += e.key.toUpperCase();
        if (gridCodeTimer) clearTimeout(gridCodeTimer);
        gridCodeTimer = setTimeout(() => {
          tryResolve(true);
          gridCodeBuffer = "";
        }, 800);

        // Immediate resolution only if no longer codes share the prefix
        const hasLongerPrefix = codeList.some(c => c.startsWith(gridCodeBuffer) && c.length > gridCodeBuffer.length);
        if (!hasLongerPrefix) {
          tryResolve(false);
        }
        break;
      }
    }
  };
  document.addEventListener("keydown", gridKeyHandler);

  // Helper to open picker
  function openShiftPicker(userId, date, currentAssignment, showOverride = false) {
    pickerContext = { userId, date, currentAssignment };
    const backdrop = document.getElementById("shiftPickerBackdrop");
    const modal = document.getElementById("shiftPickerModal");
    const title = document.getElementById("shiftPickerTitle");
    const dateLabel = document.getElementById("shiftPickerDate");
    const list = document.getElementById("shiftPickerList");
    const overrideSection = document.getElementById("overrideSection");
    const commentSection = document.getElementById("commentSection");
    const overrideStartTime = document.getElementById("overrideStartTime");
    const overrideEndTime = document.getElementById("overrideEndTime");
    const overrideHours = document.getElementById("overrideHours");
    const shiftComment = document.getElementById("shiftComment");
    const clearOverrideBtn = document.getElementById("clearOverrideBtn");
    const saveBtn = document.getElementById("shiftPickerSave");
    
    const user = getAllUsers().find(u => u.id === userId);
    const dateObj = new Date(date);
    title.textContent = user ? user.name : "Select Shift";
    dateLabel.textContent = dateObj.toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short", year: "numeric" });
    
    // Initialize selected shift
    selectedShiftId = currentAssignment?.shift_id || null;
    
    // Show override/comment sections only if showOverride is true
    if (overrideSection) overrideSection.style.display = showOverride ? "" : "none";
    if (commentSection) commentSection.style.display = showOverride ? "" : "none";
    // Save button should always be visible
    if (saveBtn) saveBtn.style.display = "";
    
    // Load existing override data if showOverride is true
    if (showOverride && typeof getOverride === "function") {
      const override = currentAssignment?.id ? getOverride(currentAssignment.id) : null;
      
      // Get shift's default times/hours for prefilling
      const currentShift = currentAssignment?.shift_id ? (getDraftShifts() || []).find(s => s.id === currentAssignment.shift_id) : null;
      
      const commentVisibilitySelect = document.getElementById("commentVisibilitySelect");
      
      if (override) {
        // Use existing override values
        if (overrideStartTime) overrideStartTime.value = override.override_start_time || "";
        if (overrideEndTime) overrideEndTime.value = override.override_end_time || "";
        if (overrideHours) overrideHours.value = override.override_hours || "";
        if (shiftComment) shiftComment.value = override.comment || "";
        if (commentVisibilitySelect) commentVisibilitySelect.value = override.comment_visibility || 'admin_only';
      } else {
        // No existing override - clear all fields
        if (overrideStartTime) overrideStartTime.value = "";
        if (overrideEndTime) overrideEndTime.value = "";
        if (overrideHours) overrideHours.value = "";
        if (shiftComment) shiftComment.value = "";
        if (commentVisibilitySelect) commentVisibilitySelect.value = 'admin_only';
      }
    }
    
    // Clear override button
    if (clearOverrideBtn) {
      clearOverrideBtn.onclick = () => {
        if (overrideStartTime) overrideStartTime.value = "";
        if (overrideEndTime) overrideEndTime.value = "";
        if (overrideHours) overrideHours.value = "";
      };
    }
    
    // Populate shift options
    list.innerHTML = "";
    list.className = "shift-picker-list";
    const shifts = (getDraftShifts() || []).filter(shiftFilterFn);
    console.log("[SHIFT PICKER] getDraftShifts() returned:", shifts);

    // Helper to check if shift object is time-off
    function isTimeOff(shiftObj) {
      if (!shiftObj) return false;
      return shiftObj.is_time_off === true;
    }

    // Sort so role-group compatible shifts appear first, but still show all options (even for admins)
    const userGroupCode = (() => {
      if (user?.role_group === 'staff_nurse') return 'SN';
      if (user?.role_group === 'nursing_assistant') return 'NA';
      if (user?.role_id === 1) return 'CN';
      if (user?.role_id === 2) return 'SN';
      if (user?.role_id === 3) return 'NA';
      return null;
    })();

    // Separate time-off from actual shifts
    const actualShifts = shifts.filter(s => !isTimeOff(s));
    const timeOffShifts = shifts.filter(s => isTimeOff(s));

    const sortedActualShifts = [...actualShifts].sort((a, b) => {
      if (!userGroupCode) return (a.code || '').localeCompare(b.code || '');
      const aAllowed = (a.allowed_staff_groups || '').includes(userGroupCode);
      const bAllowed = (b.allowed_staff_groups || '').includes(userGroupCode);
      if (aAllowed !== bAllowed) return aAllowed ? -1 : 1;
      return (a.code || '').localeCompare(b.code || '');
    });

    const sortedTimeOffShifts = [...timeOffShifts].sort((a, b) => (a.code || '').localeCompare(b.code || ''));
    
    if (!shifts || shifts.length === 0) {
      list.innerHTML = `<div style="padding:12px; text-align:center; color:#999;">No shifts available.</div>`;
      backdrop.setAttribute("aria-hidden", "false");
      return;
    }
    
    // Render actual shifts section
    if (sortedActualShifts.length > 0) {
      const shiftHeader = document.createElement("div");
      shiftHeader.className = "shift-picker-section-header";
      shiftHeader.textContent = "Shifts";
      shiftHeader.style.cssText = "padding: 10px 16px; font-weight: 600; color: #1f2937; font-size: 0.9em; background: #f3f4f6; border: 1px solid #d1d5db; border-radius: 12px; margin-bottom: 8px; grid-column: 1 / -1; text-align: center;";
      list.appendChild(shiftHeader);

      sortedActualShifts.forEach(shift => {
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "shift-card";
        btn.dataset.shiftId = shift.id;

        // Display only the code; details stay in hover
        const codeEl = document.createElement("div");
        codeEl.className = "shift-code";
        codeEl.textContent = shift.code || "Shift";

        // Apply styling from shift definitions
        if (shift.fill_color) btn.style.setProperty("--shift-fill", shift.fill_color);
        if (shift.text_color) btn.style.setProperty("--shift-text", shift.text_color);
        if (shift.fill_color) btn.style.setProperty("--shift-border", shift.fill_color);
        if (shift.text_bold) btn.classList.add("is-bold");
        if (shift.text_italic) btn.classList.add("is-italic");

        // Tooltip for fuller context
        const staffGroups = (shift.allowed_staff_groups || "").split(",").map(g => g.trim()).filter(Boolean).join(", ") || "None";
        const times = shift.start_time && shift.end_time ? `${shift.start_time} to ${shift.end_time}` : "No set times";
        const hours = shift.hours_value ? `${shift.hours_value}h` : "?h";
        const label = shift.label ? ` ${shift.label}` : "";
        const tooltip = `${shift.code}${label}\n${times}\n${hours}\nStaff: ${staffGroups}`;
        btn.title = tooltip.trim();

        if (currentAssignment && currentAssignment.shift_id === shift.id) {
          btn.classList.add("selected");
        }
        btn.addEventListener("click", () => {
          // In draft mode: save immediately (old behavior)
          if (editMode === "draft") {
            if (onSave) onSave(userId, date, shift.id, null);
            closeShiftPicker();
            return;
          }
          
          // In published mode: just select the shift
          selectedShiftId = shift.id;
          // Update UI to show selection
          list.querySelectorAll(".shift-card").forEach(c => c.classList.remove("selected"));
          btn.classList.add("selected");
        });

        btn.appendChild(codeEl);
        list.appendChild(btn);
      });
    }

    // Render time-off section
    if (sortedTimeOffShifts.length > 0) {
      const timeOffHeader = document.createElement("div");
      timeOffHeader.className = "shift-picker-section-header";
      timeOffHeader.textContent = "Time Off";
      timeOffHeader.style.cssText = "padding: 10px 16px; font-weight: 600; color: #6b7280; font-size: 0.9em; background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 12px; margin-top: 8px; margin-bottom: 8px; grid-column: 1 / -1; text-align: center;";
      list.appendChild(timeOffHeader);

      sortedTimeOffShifts.forEach(shift => {
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "shift-card time-off";
        btn.dataset.shiftId = shift.id;

        // Display only the code; details stay in hover
        const codeEl = document.createElement("div");
        codeEl.className = "shift-code";
        codeEl.textContent = shift.code || "Time Off";

        // Apply styling from shift definitions (keep the nice colors!)
        if (shift.fill_color) btn.style.setProperty("--shift-fill", shift.fill_color);
        if (shift.text_color) btn.style.setProperty("--shift-text", shift.text_color);
        if (shift.fill_color) btn.style.setProperty("--shift-border", shift.fill_color);
        if (shift.text_bold) btn.classList.add("is-bold");
        if (shift.text_italic) btn.classList.add("is-italic");

        // Tooltip for fuller context
        const label = shift.label ? ` ${shift.label}` : "";
        const tooltip = `${shift.code}${label} (Time Off)`;
        btn.title = tooltip.trim();

        if (currentAssignment && currentAssignment.shift_id === shift.id) {
          btn.classList.add("selected");
        }
        btn.addEventListener("click", () => {
          // In draft mode: save immediately (old behavior)
          if (editMode === "draft") {
            if (onSave) onSave(userId, date, shift.id, null);
            closeShiftPicker();
            return;
          }
          
          // In published mode: just select the shift
          selectedShiftId = shift.id;
          // Update UI to show selection
          list.querySelectorAll(".shift-card").forEach(c => c.classList.remove("selected"));
          btn.classList.add("selected");
        });

        btn.appendChild(codeEl);
        list.appendChild(btn);
      });
    }

    // Add clear option (matches request picker affordance)
    const clearBtnCard = document.createElement("button");
    clearBtnCard.type = "button";
    clearBtnCard.className = "shift-card clear";
    clearBtnCard.textContent = "Clear";
    clearBtnCard.title = "Remove the assigned shift";
    clearBtnCard.addEventListener("click", () => {
      if (onClear) onClear(userId, date);
      closeShiftPicker();
    });
    list.appendChild(clearBtnCard);
    backdrop.setAttribute("aria-hidden", "false");

    // Keyboard shorthand: type codes like N / LD / 8-8 to select, Backspace clears
    detachPickerKeys();
    pickerKeyBuffer = "";
    pickerKeyHandler = (e) => {
      const backdrop = document.getElementById("shiftPickerBackdrop");
      if (backdrop.getAttribute("aria-hidden") !== "false") return;
      if (["Meta", "Control", "Alt"].includes(e.key)) return;
      
      // Ignore all keyboard shortcuts when typing in text fields
      const target = e.target;
      if (target && (target.tagName === "INPUT" || target.tagName === "TEXTAREA")) return;

      // Escape closes
      if (e.key === "Escape") {
        closeShiftPicker();
        return;
      }

      // Backspace: if buffer empty, clear assignment (only in draft mode)
      if (e.key === "Backspace") {
        if (!pickerKeyBuffer && editMode === "draft") {
          e.preventDefault();
          if (onClear) onClear(userId, date);
          closeShiftPicker();
          return;
        }
        pickerKeyBuffer = pickerKeyBuffer.slice(0, -1);
        return;
      }

      const allowed = /^[a-zA-Z0-9*\-]$/;
      if (!allowed.test(e.key)) return;

      pickerKeyBuffer += e.key.toUpperCase();
      if (pickerKeyTimer) clearTimeout(pickerKeyTimer);
      pickerKeyTimer = setTimeout(() => { pickerKeyBuffer = ""; }, 75);

      const resolution = resolveShiftByCode(pickerKeyBuffer, userId, shifts);
      if (!resolution) return;

      if (resolution.ambiguous) {
        alert(`Shift code "${pickerKeyBuffer}" is ambiguous. Please pick manually.`);
        return;
      }

      // In draft mode: save immediately
      if (editMode === "draft") {
        if (onSave) onSave(userId, date, resolution.id, null);
        closeShiftPicker();
        return;
      }
      
      // In published mode: just select the shift (user must click Save)
      selectedShiftId = resolution.id;
      const list = document.getElementById("shiftPickerList");
      if (list) {
        list.querySelectorAll(".shift-card").forEach(c => c.classList.remove("selected"));
        const selectedCard = list.querySelector(`[data-shift-id="${resolution.id}"]`);
        if (selectedCard) selectedCard.classList.add("selected");
      }
    };
    document.addEventListener("keydown", pickerKeyHandler);
  }

  // Expose picker opener for published Change Shift flow (uses closures above)
  window.openShiftPickerForPublished = function(userId, date) {
    if (!window.PermissionsModule?.hasPermission(editPermissionKey)) {
      alert("You don't have permission to edit this rota.");
      return;
    }

    const assignment = getAssignment(userId, date);
    // Temporarily mark unlocked for the action to reuse picker UI
    isEditingUnlocked = true;
    const btn = document.getElementById("toggleEditingBtn");
    if (btn) {
      btn.textContent = unlockedLabel;
      btn.classList.add("primary");
    }
    document.querySelectorAll("#rota td.cell").forEach(td => td.classList.toggle("editable", isEditingUnlocked));
    openShiftPicker(userId, date, assignment, false);  // showOverride = false
  };

  function closeShiftPicker() {
    const backdrop = document.getElementById("shiftPickerBackdrop");
    if (backdrop) backdrop.setAttribute("aria-hidden", "true");
    pickerContext = null;
    detachPickerKeys();
  }

  function clearShiftAssignment() {
    if (!pickerContext) return;
    const { userId, date, currentAssignment } = pickerContext;
    if (!currentAssignment) {
      closeShiftPicker();
      return;
    }
    if (onClear) onClear(userId, date);
    closeShiftPicker();
  }

  function saveShiftAssignment() {
    if (!pickerContext) return;
    const { userId, date } = pickerContext;
    
    if (!selectedShiftId) {
      alert("Please select a shift first");
      return;
    }
    
    // Collect override data if in published mode
    let overrideData = null;
    if (editMode === "published") {
      const startTime = document.getElementById("overrideStartTime")?.value?.trim() || null;
      const endTime = document.getElementById("overrideEndTime")?.value?.trim() || null;
      const hoursValue = document.getElementById("overrideHours")?.value?.trim();
      const hours = hoursValue ? parseFloat(hoursValue) : null;
      const comment = document.getElementById("shiftComment")?.value?.trim() || null;
      const commentVisibility = document.getElementById("commentVisibilitySelect")?.value || 'admin_only';
      
      console.log("[SHIFT PICKER SAVE] Override data:", { startTime, endTime, hours, comment, commentVisibility });
      
      // Only create override if at least one field has a value
      if (startTime || endTime || hours || comment) {
        overrideData = {
          override_start_time: startTime,
          override_end_time: endTime,
          override_hours: hours,
          comment: comment,
          comment_visibility: commentVisibility
        };
        console.log("[SHIFT PICKER SAVE] Created overrideData:", overrideData);
      } else {
        console.log("[SHIFT PICKER SAVE] No override fields filled");
      }
    }
    
    console.log("[SHIFT PICKER SAVE] Calling onSave with:", { userId, date, selectedShiftId, overrideData });
    if (onSave) onSave(userId, date, selectedShiftId, overrideData);
    closeShiftPicker();
  }

  function resolveShiftByCode(code, userId, shifts) {
    const norm = (code || "").trim().toUpperCase();
    if (!norm) return null;

    const user = getAllUsers().find(u => u.id === userId);
    const userName = (user?.name || "").toLowerCase();
    const isPaulBoso = userName.includes("paul") && userName.includes("boso");
    
    let staffGroup = ROLE_TO_STAFF_GROUP_EDIT[user?.role_id] || null;
    
    console.log("[RESOLVE SHIFT] Code:", norm, "User:", userName, "Staff Group:", staffGroup, "Is Paul:", isPaulBoso);

    const matches = (shifts || []).filter(s => (s.code || "").toUpperCase() === norm);
    console.log("[RESOLVE SHIFT] Matches found:", matches.length, matches.map(s => `${s.code} (${s.hours_value}h)`));
    if (matches.length === 0) return null;
    if (matches.length === 1) return matches[0];

    // Special handling for "N" code based on role
    if (norm === "N" && staffGroup) {
      const filtered = matches.filter(s => {
        const allowed = (s.allowed_staff_groups || "").toUpperCase().split(",").map(x => x.trim()).filter(Boolean);
        return allowed.includes(staffGroup);
      });
      
      console.log("[RESOLVE N] Filtered by staff group:", filtered.map(s => `${s.code} (${s.hours_value}h, groups: ${s.allowed_staff_groups})`));
      
      if (filtered.length > 0) {
        // CN or SN (except Paul): choose 12.5hr version
        if ((staffGroup === "CN" || staffGroup === "SN") && !isPaulBoso) {
          const maxHours = Math.max(...filtered.map(s => Number(s.hours_value) || 0));
          const top = filtered.filter(s => (Number(s.hours_value) || 0) === maxHours);
          console.log("[RESOLVE N] CN/SN - selecting max hours:", maxHours, "Result:", top[0]);
          if (top.length >= 1) return top[0]; // Return first if multiple with same max hours
        }
        // NA or Paul: choose 12hr version
        else if (staffGroup === "NA" || isPaulBoso) {
          const minHours = Math.min(...filtered.map(s => Number(s.hours_value) || 999));
          const low = filtered.filter(s => (Number(s.hours_value) || 999) === minHours);
          console.log("[RESOLVE N] NA/Paul - selecting min hours:", minHours, "Result:", low[0]);
          if (low.length >= 1) return low[0]; // Return first if multiple with same min hours
        }
        // Fallback: just return first filtered
        if (filtered.length === 1) return filtered[0];
      }
    }

    // General disambiguation by staff group for other codes
    if (staffGroup) {
      const filtered = matches.filter(s => {
        const allowed = (s.allowed_staff_groups || "").toUpperCase().split(",").map(x => x.trim()).filter(Boolean);
        return allowed.includes(staffGroup);
      });
      console.log("[RESOLVE GENERAL] Filtered:", filtered.length);
      if (filtered.length === 1) return filtered[0];
      if (filtered.length > 0) return filtered[0]; // Just pick first match if multiple

      // Heuristic: choose hours by band (CN/SN -> max hours; NA -> min hours)
      if (filtered.length > 1) {
        if (staffGroup === "CN" || staffGroup === "SN") {
          const maxHours = Math.max(...filtered.map(s => Number(s.hours_value) || 0));
          const top = filtered.filter(s => (Number(s.hours_value) || 0) === maxHours);
          if (top.length >= 1) return top[0];
        } else if (staffGroup === "NA") {
          const minHours = Math.min(...filtered.map(s => Number(s.hours_value) || 999));
          const low = filtered.filter(s => (Number(s.hours_value) || 999) === minHours);
          if (low.length >= 1) return low[0];
        }
      }
    }

    // No staff group filtering worked, just return first match
    console.log("[RESOLVE GENERAL] Returning first match as fallback");
    return matches[0];
  }

  function detachPickerKeys() {
    if (pickerKeyTimer) {
      clearTimeout(pickerKeyTimer);
      pickerKeyTimer = null;
    }
    pickerKeyBuffer = "";
    if (pickerKeyHandler) {
      document.removeEventListener("keydown", pickerKeyHandler);
      pickerKeyHandler = null;
    }
  }

  function detachGridKeys() {
    if (gridKeyHandler) {
      document.removeEventListener("keydown", gridKeyHandler);
      gridKeyHandler = null;
    }
    if (gridCodeTimer) {
      clearTimeout(gridCodeTimer);
      gridCodeTimer = null;
    }
    gridCodeBuffer = "";
  }

  function setFocusedCell(td) {
    if (focusedCell === td) return;
    if (focusedCell) focusedCell.classList.remove("focused");
    focusedCell = td;
    lastFocusKey = td ? `${td.dataset.userId}_${td.dataset.date}` : null;
    if (focusedCell) focusedCell.classList.add("focused");
  }
}

// Expose init for inline boot in rota.html
window.initDraftEditing = initDraftEditing;
window.setShiftEditContext = function({
  permissionKey = "rota.edit_draft",
  contextLabel = "draft rota",
  mode = "draft",
  lockedLabelText = "🔒 Locked",
  unlockedLabelText = "🔓 Editing",
  shiftFilter = null
} = {}) {
  editPermissionKey = permissionKey;
  editContextLabel = contextLabel;
  editMode = mode === "published" ? "published" : "draft";
  lockedLabel = lockedLabelText;
  unlockedLabel = unlockedLabelText;
  shiftFilterFn = typeof shiftFilter === "function" ? shiftFilter : () => true;

  // Reset button label to locked state (state remains until resetEditingLock invoked)
  const btn = document.getElementById("toggleEditingBtn");
  if (btn) btn.textContent = lockedLabel;
};

window.resetEditingLock = function() {
  isEditingUnlocked = false;
  const btn = document.getElementById("toggleEditingBtn");
  if (btn) {
    btn.textContent = lockedLabel;
    btn.classList.remove("primary");
  }
  document.querySelectorAll("#rota td.cell").forEach(td => td.classList.toggle("editable", isEditingUnlocked));
};


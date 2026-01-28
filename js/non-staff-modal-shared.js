// non-staff-modal-shared.js
// Shared non-staff modal functionality for rota.html and other pages

console.log("[NON-STAFF-MODAL-SHARED.JS] Script loaded");

let selectedNonStaffForDelete = null;

// ========== MODAL OPEN/CLOSE ==========

function openNonStaffModal() {
  const backdrop = document.getElementById('nonStaffModalBackdrop');
  if (!backdrop) return;
  
  const hasStudentPerm = window.PermissionsModule?.hasPermission?.('non_staff.add_student');
  const hasBankAgencyPerm = window.PermissionsModule?.hasPermission?.('non_staff.add_bank_agency');
  
  // Users with only student permission default to students and lock categories
  const categorySel = document.getElementById('nsCategory');
  const categorySelCreate = document.getElementById('nsCategoryCreate');
  const canOnlyAddStudents = hasStudentPerm && !hasBankAgencyPerm && !window.currentUser?.is_admin;
  
  if (categorySel) {
    categorySel.value = canOnlyAddStudents ? 'student' : categorySel.value || 'student';
    categorySel.disabled = canOnlyAddStudents;
  }
  if (categorySelCreate) {
    categorySelCreate.value = canOnlyAddStudents ? 'student' : categorySelCreate.value || 'student';
    categorySelCreate.disabled = canOnlyAddStudents;
  }
  
  // Initialize role group + counts UI for default (student)
  updateNonStaffModalFields();
  updateNonStaffModalFieldsCreate();
  
  document.getElementById('nsSearch')?.setAttribute('value','');
  document.getElementById('nsResults').innerHTML = '';
  document.getElementById('nsNewName').value = '';
  
  // Auto-load existing non-staff for this period
  loadExistingNonStaff();
  
  // Switch to Select tab by default
  switchNonStaffTab('select');
  
  backdrop.setAttribute('aria-hidden','false');
}

function loadExistingNonStaff() {
  const resultsEl = document.getElementById('nsResults');
  if (!resultsEl) return;
  
  // Get non-staff already assigned to current period
  const currentPeriodId = window.currentPeriod?.id || window.periodData?.id;
  if (!currentPeriodId) {
    resultsEl.innerHTML = '<div style="color:#64748b;">No period selected.</div>';
    return;
  }
  
  // Query the non-staff already loaded (from loadPeriod)
  const periodNonStaff = window.nonStaff || [];
  
  if (periodNonStaff.length === 0) {
    resultsEl.innerHTML = '<div style="color:#64748b;">No non-staff assigned to this period yet.</div>';
    return;
  }
  
  // Display existing non-staff with remove button
  resultsEl.innerHTML = '';
  periodNonStaff.forEach(row => {
    const line = document.createElement('div');
    line.style.display = 'flex';
    line.style.justifyContent = 'space-between';
    line.style.alignItems = 'center';
    line.style.padding = '8px 6px';
    line.style.borderRadius = '4px';
    line.style.transition = 'background 200ms';
    line.style.backgroundColor = '#f0fdf4';
    line.style.borderLeft = '3px solid #22c55e';

    line.addEventListener('mouseenter', () => { line.style.background = '#dbeafe'; });
    line.addEventListener('mouseleave', () => { line.style.background = '#f0fdf4'; });

    const left = document.createElement('div');
    left.textContent = `${row.name} · ${row.category}${row.role_group ? ' · ' + row.role_group : ''}`;
    left.style.cursor = 'pointer';
    left.addEventListener('click', () => {
      selectedNonStaffForDelete = row;
      showDeleteSection(row);
    });

    const btn = document.createElement('button');
    btn.textContent = 'Remove';
    btn.style.whiteSpace = 'nowrap';
    btn.style.padding = '4px 8px';
    btn.style.background = '#dc2626';
    btn.style.color = 'white';
    btn.style.border = 'none';
    btn.style.borderRadius = '4px';
    btn.style.cursor = 'pointer';
    btn.style.fontSize = '12px';
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      selectedNonStaffForDelete = row;
      deleteSelectedNonStaff();
    });

    line.appendChild(left);
    line.appendChild(btn);
    resultsEl.appendChild(line);
  });
}

function closeNonStaffModal() {
  const backdrop = document.getElementById('nonStaffModalBackdrop');
  const nsSearch = document.getElementById('nsSearch');
  const nsResults = document.getElementById('nsResults');
  
  // Clear search input and results
  if (nsSearch) nsSearch.value = '';
  if (nsResults) nsResults.innerHTML = '';
  
  // Hide the modal
  if (backdrop) backdrop.setAttribute('aria-hidden','true');
}

// ========== SEARCH NON-STAFF ==========

async function searchNonStaff() {
  const category = document.getElementById('nsCategory')?.value || null;
  const roleGroup = (category === 'student') ? null : (document.getElementById('nsRoleGroup')?.value || null);   
  const query = document.getElementById('nsSearch')?.value || null;
  const resultsEl = document.getElementById('nsResults');
  
  if (!resultsEl) return;
  
  resultsEl.innerHTML = '<div style="color:#64748b;">Searching...</div>';
  
  try {
    const { data, error } = await supabaseClient.rpc('rpc_list_non_staff_people', {
      p_token: window.currentToken,
      p_category: category,
      p_role_group: roleGroup,
      p_query: query
    });
    
    if (error) throw error;
    
    if (!data || data.length === 0) {
      resultsEl.innerHTML = '<div style="color:#64748b;">No matches.</div>';
      return;
    }
    
    resultsEl.innerHTML = '';
    
    data.forEach(row => {
      const line = document.createElement('div');
      line.style.display = 'flex';
      line.style.justifyContent = 'space-between';
      line.style.alignItems = 'center';
      line.style.padding = '8px 6px';
      line.style.cursor = 'pointer';
      line.style.borderRadius = '4px';
      line.style.transition = 'background 200ms';

      line.addEventListener('mouseenter', () => { line.style.background = '#f1f5f9'; });
      line.addEventListener('mouseleave', () => { line.style.background = ''; });
      line.addEventListener('click', () => {
        selectedNonStaffForDelete = row;
        showDeleteSection(row);
      });

      const left = document.createElement('div');
      left.textContent = `${row.name} · ${row.category}${row.role_group ? ' · ' + row.role_group : ''}`;       
      
      const btn = document.createElement('button');
      btn.textContent = 'Add';
      btn.style.whiteSpace = 'nowrap';
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        addExistingNonStaff(row.id, row.category);
      });
      
      line.appendChild(left);
      line.appendChild(btn);
      resultsEl.appendChild(line);
    });
  } catch (e) {
    resultsEl.innerHTML = `<div style="color:#dc2626;">Error: ${e?.message || e}</div>`;
  }
}

// ========== ADD NON-STAFF ==========

async function addExistingNonStaff(nonStaffPersonId, category) {
  const counts = document.getElementById('nsCounts');
  const countsVal = counts?.checked ?? (category !== 'student');
  
  try {
    const { data, error } = await supabaseClient.rpc('rpc_add_non_staff_to_period', {
      p_token: window.currentToken,
      p_period_id: window.currentPeriod?.id || window.periodData?.id,
      p_non_staff_person_id: nonStaffPersonId,
      p_counts_towards_staffing: countsVal,
      p_display_order: 9999
    });
    
    if (error) throw error;
    
    // Check if the RPC function returned an error in the JSON response
    if (data && !data.success) {
      throw new Error(data.error || 'Failed to add non-staff to period');
    }
    
    closeNonStaffModal();
    
    // Reload period data
    if (typeof loadPeriod === 'function' && (window.currentPeriod?.id || window.periodData?.id)) {
      await loadPeriod(window.currentPeriod?.id || window.periodData?.id);
    }
  } catch (e) {
    alert('Failed to add: ' + (e?.message || e));
  }
}

async function addNewNonStaff() {
  const name = document.getElementById('nsNewName')?.value?.trim();
  const category = document.getElementById('nsCategoryCreate')?.value;
  const roleGroup = category === 'student' ? null : document.getElementById('nsRoleGroupCreate')?.value;
  const counts = (category === 'student') ? false : true;
  
  if (!name) {
    alert('Enter a name for the new profile.');
    return;
  }
  
  try {
    const { data: created, error: addErr } = await supabaseClient.rpc('rpc_add_non_staff_person', {
      p_token: window.currentToken,
      p_name: name,
      p_category: category,
      p_role_group: roleGroup,
      p_notes: null
    });
    
    if (addErr) throw addErr;
    
    // Check if the RPC function returned an error in the JSON response
    if (created && !created.success) {
      throw new Error(created.error || 'Failed to create non-staff person');
    }
    
    const newId = created?.id;
    if (!newId) throw new Error('Create returned no id');
    
    await addExistingNonStaff(newId, category);
  } catch (e) {
    alert('Failed to create/add: ' + (e?.message || e));
  }
}

// ========== DELETE NON-STAFF ==========

function showDeleteSection(item) {
  const deleteSection = document.getElementById('nsDeleteSection');
  const deleteItemName = document.getElementById('nsDeleteItemName');
  const isMentor = window.PermissionsModule?.hasPermission?.('non_staff.edit_student_shifts');

  // Only show delete if admin or mentor (for students)
  const canDelete = window.currentUser?.is_admin || (isMentor && item.category === 'student');
  
  if (!canDelete) {
    deleteSection.style.display = 'none';
    return;
  }

  deleteItemName.textContent = `${item.name} (${item.category})`;
  deleteSection.style.display = 'block';
}

async function deleteSelectedNonStaff() {
  if (!selectedNonStaffForDelete || !selectedNonStaffForDelete.period_non_staff_id) {
    alert('No item selected for deletion');
    return;
  }

  const confirmMsg = `Remove ${selectedNonStaffForDelete.name} from this period?`;
  if (!confirm(confirmMsg)) return;

  try {
    const { error } = await supabaseClient.rpc('rpc_remove_non_staff_from_period', {
      p_token: window.currentToken,
      p_period_non_staff_id: selectedNonStaffForDelete.period_non_staff_id
    });
    
    if (error) throw error;
    
    selectedNonStaffForDelete = null;
    document.getElementById('nsDeleteSection').style.display = 'none';
    
    // Reload period data
    if (typeof loadPeriod === 'function' && (window.currentPeriod?.id || window.periodData?.id)) {
      await loadPeriod(window.currentPeriod?.id || window.periodData?.id);
    }
  } catch (e) {
    alert('Failed to remove: ' + (e?.message || e));
  }
}

// ========== TAB SWITCHING ==========

function switchNonStaffTab(tab) {
  const selectSection = document.getElementById('nsSelectSection');
  const createSection = document.getElementById('nsCreateSection');
  const tabSelect = document.getElementById('nsTabSelect');
  const tabCreate = document.getElementById('nsTabCreate');

  if (tab === 'select') {
    if (selectSection) selectSection.style.display = 'block';
    if (createSection) createSection.style.display = 'none';
    if (tabSelect) {
      tabSelect.style.color = '#0f172a';
      tabSelect.style.borderBottomColor = '#3b82f6';
    }
    if (tabCreate) {
      tabCreate.style.color = '#94a3b8';
      tabCreate.style.borderBottomColor = 'transparent';
    }
  } else {
    if (selectSection) selectSection.style.display = 'none';
    if (createSection) createSection.style.display = 'block';
    if (tabSelect) {
      tabSelect.style.color = '#94a3b8';
      tabSelect.style.borderBottomColor = 'transparent';
    }
    if (tabCreate) {
      tabCreate.style.color = '#0f172a';
      tabCreate.style.borderBottomColor = '#3b82f6';
    }
  }
}

// ========== FIELD UPDATES ==========

function updateNonStaffModalFields(){
  const category = document.getElementById('nsCategory')?.value;
  const roleWrap = document.getElementById('nsRoleGroupWrap');
  const countsWrap = document.getElementById('nsCountsWrap');
  const counts = document.getElementById('nsCounts');
  
  if (!category) return;
  
  if (category === 'student'){
    if (roleWrap) roleWrap.style.display = 'none';
    if (countsWrap) countsWrap.style.display = 'none';
    if (counts) { counts.checked = false; counts.disabled = true; }
  } else if (category === 'agency') {
    if (roleWrap) roleWrap.style.display = '';
    if (countsWrap) countsWrap.style.display = '';
    if (counts) { counts.checked = true; counts.disabled = true; }
  } else {
    // bank: allow toggle
    if (roleWrap) roleWrap.style.display = '';
    if (countsWrap) countsWrap.style.display = '';
    if (counts) { counts.disabled = false; }
  }
}

function updateNonStaffModalFieldsCreate(){
  const category = document.getElementById('nsCategoryCreate')?.value;
  const roleWrap = document.getElementById('nsRoleGroupCreateWrap');
  const countsWrap = document.getElementById('nsCountsWrap');
  const counts = document.getElementById('nsCounts');
  
  if (!category) return;
  
  if (category === 'student'){
    if (roleWrap) roleWrap.style.display = 'none';
    if (countsWrap) countsWrap.style.display = 'none';
    if (counts) { counts.checked = false; counts.disabled = true; }
  } else if (category === 'agency') {
    if (roleWrap) roleWrap.style.display = '';
    if (countsWrap) countsWrap.style.display = '';
    if (counts) { counts.checked = true; counts.disabled = true; }
  } else {
    // bank: allow toggle
    if (roleWrap) roleWrap.style.display = '';
    if (countsWrap) countsWrap.style.display = '';
    if (counts) { counts.disabled = false; }
  }
}

// ========== EXPORT TO WINDOW ==========
// Make all key functions available globally for rota.html and other pages
window.openNonStaffModal = openNonStaffModal;
window.closeNonStaffModal = closeNonStaffModal;
window.searchNonStaff = searchNonStaff;
window.addExistingNonStaff = addExistingNonStaff;
window.addNewNonStaff = addNewNonStaff;
window.deleteSelectedNonStaff = deleteSelectedNonStaff;
window.switchNonStaffTab = switchNonStaffTab;
window.updateNonStaffModalFields = updateNonStaffModalFields;

// ========== INITIALIZATION ==========
// Set up event listeners for tabs when DOM is ready
function initializeNonStaffModal() {
  const tabSelect = document.getElementById('nsTabSelect');
  const tabCreate = document.getElementById('nsTabCreate');
  const closeBtn = document.getElementById('nsCloseBtn');
  const searchBtn = document.getElementById('nsSearchBtn');
  const backdrop = document.getElementById('nonStaffModalBackdrop');
  
  if (tabSelect) {
    tabSelect.addEventListener('click', () => switchNonStaffTab('select'));
  }
  if (tabCreate) {
    tabCreate.addEventListener('click', () => switchNonStaffTab('create'));
  }
  if (closeBtn) {
    closeBtn.addEventListener('click', closeNonStaffModal);
  }
  if (searchBtn) {
    searchBtn.addEventListener('click', searchNonStaff);
  }
  // Close modal when clicking on the backdrop
  if (backdrop) {
    backdrop.addEventListener('click', (e) => {
      if (e.target === backdrop) {
        closeNonStaffModal();
      }
    });
  }
}

// Initialize when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initializeNonStaffModal);
} else {
  initializeNonStaffModal();
}
window.updateNonStaffModalFieldsCreate = updateNonStaffModalFieldsCreate;
window.loadExistingNonStaff = loadExistingNonStaff;
console.log("[NON-STAFF-MODAL-SHARED.JS] Functions exported to window");

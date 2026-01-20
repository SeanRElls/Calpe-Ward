// Rota context menu for admin actions on cells
(function () {
  let menuEl = null;
  let current = null;

  function init() {
    createMenu();
    // Use document-level capture listener so late-rendered rota table cells are caught
    document.addEventListener('contextmenu', onContextMenu, true);
    document.addEventListener('click', hideMenu, true);
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') hideMenu();
    });
  }

  function createMenu() {
    menuEl = document.createElement('div');
    menuEl.id = 'rotaContextMenu';
    menuEl.style.position = 'fixed';
    menuEl.style.zIndex = '9999';
    menuEl.style.minWidth = '180px';
    menuEl.style.background = '#fff';
    menuEl.style.border = '1px solid #d0d0d0';
    menuEl.style.boxShadow = '0 4px 12px rgba(0,0,0,0.15)';
    menuEl.style.borderRadius = '6px';
    menuEl.style.padding = '4px 0';
    menuEl.style.fontSize = '14px';
    menuEl.style.display = 'none';

    const items = [
      { id: 'history', label: 'View history', action: doHistory },
      { id: 'swap', label: 'Swap shift', action: doSwap },
      { id: 'change', label: 'Change shift', action: doChange },
      { id: 'override', label: 'Override shift', action: doOverride }
    ];

    items.forEach(item => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.style.display = 'block';
      btn.style.width = '100%';
      btn.style.textAlign = 'left';
      btn.style.padding = '8px 12px';
      btn.style.border = 'none';
      btn.style.background = 'transparent';
      btn.style.cursor = 'pointer';
      btn.textContent = item.label;
      btn.addEventListener('click', () => {
        item.action();
        hideMenu();
      });
      btn.addEventListener('mouseenter', () => btn.style.background = '#f3f4f6');
      btn.addEventListener('mouseleave', () => btn.style.background = 'transparent');
      menuEl.appendChild(btn);
    });

    document.body.appendChild(menuEl);
  }

  function onContextMenu(e) {
    const cell = e.target.closest('td.cell');
    if (!cell) return;
    if (!window.currentUser?.is_admin) {
      console.log('[CONTEXT MENU] User is not admin, skipping');
      return;
    }

    console.log('[CONTEXT MENU] Right-click on cell detected');
    
    // Always suppress native menu for admin rota cells
    e.preventDefault();
    e.stopPropagation();
    e.stopImmediatePropagation();

    const isPublishedContext = (window.currentEditContext === 'published') || (window.periodData?.status === 'published');
    console.log('[CONTEXT MENU] isPublishedContext:', isPublishedContext, 'currentEditContext:', window.currentEditContext, 'periodStatus:', window.periodData?.status);
    if (!isPublishedContext) {
      console.log('[CONTEXT MENU] Not in published context, skipping');
      return;
    }

    const userId = cell.dataset.userId;
    const date = cell.dataset.date;
    const assignmentId = cell.dataset.assignmentId;
    
    // Allow menu for cells with or without assignments
    if (!userId || !date) {
      console.log('[CONTEXT MENU] Missing userId or date');
      return;
    }
    
    current = { 
      assignmentId: assignmentId ? Number(assignmentId) : null, 
      userId, 
      date 
    };
    
    console.log('[CONTEXT MENU] Showing menu for:', current);
    showMenu(e.clientX, e.clientY);
  }

  function showMenu(x, y) {
    if (!menuEl || !current) return;
    menuEl.style.left = `${x + 4}px`;
    menuEl.style.top = `${y + 4}px`;
    menuEl.style.display = 'block';
  }

  function hideMenu(e) {
    if (e && menuEl && menuEl.contains(e.target)) return; // keep menu open when clicking inside
    if (menuEl) menuEl.style.display = 'none';
    current = null;
  }

  function ensureActiveCell() {
    if (!current) return false;
    window.activeCell = { userId: current.userId, date: current.date };
    window.lastPublishedCell = { userId: current.userId, date: current.date };
    return true;
  }

  function doHistory() {
    if (!current) {
      console.log('[CONTEXT MENU] No current cell');
      return;
    }
    
    console.log('[CONTEXT MENU] doHistory called for userId:', current.userId, 'date:', current.date);
    if (window.AssignmentHistoryModule?.loadAssignmentHistory) {
      console.log('[CONTEXT MENU] Calling loadAssignmentHistory');
      window.AssignmentHistoryModule.loadAssignmentHistory(current.userId, current.date);
    } else {
      console.error('[CONTEXT MENU] AssignmentHistoryModule not available');
      alert('History module not loaded.');
    }
  }

  function doSwap() {
    if (!ensureActiveCell()) return;
    if (typeof window.handlePublishedSwap === 'function') {
      window.handlePublishedSwap();
    } else {
      alert('Swap handler not ready.');
    }
  }

  function doChange() {
    console.log('[CONTEXT MENU] doChange called');
    console.log('[CONTEXT MENU] current:', current);
    console.log('[CONTEXT MENU] ensureActiveCell result:', ensureActiveCell());
    console.log('[CONTEXT MENU] window.lastPublishedCell set to:', window.lastPublishedCell);
    
    if (!ensureActiveCell()) {
      console.log('[CONTEXT MENU] ensureActiveCell failed');
      return;
    }
    if (typeof window.handlePublishedChange === 'function') {
      console.log('[CONTEXT MENU] Calling handlePublishedChange');
      window.handlePublishedChange();
    } else {
      console.error('[CONTEXT MENU] handlePublishedChange not available');
      alert('Change handler not ready.');
    }
  }

  function doOverride() {
    console.log('[CONTEXT MENU] doOverride called');
    if (!ensureActiveCell()) {
      console.log('[CONTEXT MENU] ensureActiveCell failed');
      return;
    }
    if (typeof window.handlePublishedOverride === 'function') {
      console.log('[CONTEXT MENU] Calling handlePublishedOverride');
      window.handlePublishedOverride();
    } else {
      console.error('[CONTEXT MENU] handlePublishedOverride not available');
      alert('Override handler not ready.');
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();

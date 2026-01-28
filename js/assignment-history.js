// Assignment History Module
// Provides right-click context menu and history display for rota cells

const AssignmentHistoryModule = (() => {
  let historyModal = null;
  let currentUserId = null;
  let currentDate = null;

  const init = () => {
    createHistoryModal();
    attachContextMenuListeners();
  };

  const createHistoryModal = () => {
    const modal = document.createElement('div');
    modal.id = 'assignmentHistoryModal';
    modal.className = 'modal-backdrop';
    modal.setAttribute('aria-hidden', 'true');
    modal.innerHTML = `
      <div class="modal" style="width: min(900px, 95%);">
        <h2 style="margin: 0 0 8px 0; font-size: 17px; font-weight: 700;">Assignment History</h2>
        <div class="modal-bubble" style="max-height: 400px; overflow-y: auto; overflow-x: auto;">
          <div id="historyContent">
            <p>Loading...</p>
          </div>
        </div>
        <div class="btns">
          <button id="closeHistoryModal" type="button">Close</button>
        </div>
      </div>
    `;
    document.body.appendChild(modal);
    historyModal = modal;

    // Close button
    const closeBtn = document.getElementById('closeHistoryModal');
    if (closeBtn) {
      closeBtn.addEventListener('click', () => {
        console.log('[HISTORY] Close button clicked');
        historyModal.setAttribute('aria-hidden', 'true');
      });
    }

    // Click backdrop to close
    modal.addEventListener('click', (e) => {
      if (e.target === modal) {
        console.log('[HISTORY] Backdrop clicked');
        modal.setAttribute('aria-hidden', 'true');
      }
    });
  };

  const attachContextMenuListeners = () => {
    // Context menu is now handled by rota-context-menu.js; skip legacy binding
  };

  const handleCellContextMenu = async (e) => {
    // Check if user is admin
    if (!window.currentUser?.is_admin) return;
    const isPublishedContext = (window.currentEditContext === 'published') || (window.periodData?.status === 'published');
    if (!isPublishedContext) return; // only allow in published mode

    e.preventDefault();

    // Find the cell (can be empty or filled)
    const cell = e.target.closest('td.cell');
    if (!cell) return;

    const userId = cell.dataset.userId;
    const date = cell.dataset.date;
    if (!userId || !date) return;

    currentUserId = userId;
    currentDate = date;

    // Show context menu or directly load history
    await loadAssignmentHistory(userId, date);
  };

  const loadAssignmentHistory = async (userId, date) => {
    try {
      console.log('[HISTORY] loadAssignmentHistory called with userId:', userId, 'date:', date);
      
      if (!window.supabaseClient || !window.currentToken) {
        console.error('[HISTORY] Not authenticated');
        alert('Not authenticated');
        return;
      }

      const content = document.getElementById('historyContent');
      if (!content) {
        console.error('[HISTORY] historyContent element not found');
        return;
      }
      content.innerHTML = '<p>Loading...</p>';

      // Load shifts if not already loaded
      let shiftsByCode = new Map();
      if (window.shiftMap && window.shiftMap.size > 0) {
        // Build a code -> shift lookup from existing shiftMap
        window.shiftMap.forEach(shift => {
          if (shift.code) shiftsByCode.set(shift.code, shift);
        });
      } else {
        // Fetch shifts if not available
        const { data: shifts, error: shiftsErr } = await window.supabaseClient.rpc('rpc_get_shifts', {
          p_token: window.currentToken
        });
        if (!shiftsErr && shifts) {
          shifts.forEach(shift => {
            if (shift.code) shiftsByCode.set(shift.code, shift);
          });
        }
      }

      // Call RPC to get history by user_id + date
      console.log('[HISTORY] Calling admin_get_assignment_history_by_date RPC');
      const { data, error } = await window.supabaseClient.rpc(
        'admin_get_assignment_history_by_date',
        {
          p_token: window.currentToken,
          p_user_id: userId,
          p_date: date
        }
      );

      if (error) {
        console.error('[HISTORY] RPC error (full):', JSON.stringify(error, null, 2));
        console.error('[HISTORY] Error object:', error);
        console.error('[HISTORY] Error properties:', {
          message: error.message,
          details: error.details,
          hint: error.hint,
          code: error.code,
          statusCode: error.statusCode,
          status: error.status
        });
        
        // Show user-friendly error message
        let errorMessage = error.message || error.details || error.hint || 'Unknown error';
        
        content.innerHTML = `<p style="color: #dc2626; font-size: 13px; padding: 10px;">Error: ${errorMessage}</p>`;
        return;
      }

      console.log('[HISTORY] RPC returned data:', data);
      console.log('[HISTORY] First record keys:', data && data.length > 0 ? Object.keys(data[0]) : 'no data');

      if (!data || data.length === 0) {
        content.innerHTML = '<p style="color: #666; font-size: 13px;">No history for this assignment.</p>';
      } else {
        content.innerHTML = renderHistoryTable(data, shiftsByCode);
      }

      if (historyModal) {
        console.log('[HISTORY] Opening history modal');
        historyModal.setAttribute('aria-hidden', 'false');
      } else {
        console.error('[HISTORY] historyModal not found');
      }
    } catch (err) {
      console.error('[HISTORY] Error loading assignment history:', err);
      const content = document.getElementById('historyContent');
      if (content) {
        content.innerHTML = 
          `<p style="color: red; font-size: 13px;">Error loading history: ${err.message}</p>`;
      }
      if (historyModal) {
        historyModal.setAttribute('aria-hidden', 'false');
      }
    }
  };

  const renderHistoryTable = (records, shiftsByCode) => {
    const formatShiftCode = (code) => {
      if (!code || code === '—') return '—';
      const shift = shiftsByCode ? shiftsByCode.get(code) : null;
      if (!shift) return code;
      
      const fillColor = shift.fill_color || '#f7f7f7';
      const textColor = shift.text_color || '#333';
      const fontWeight = shift.text_bold ? '700' : '600';
      const fontStyle = shift.text_italic ? 'italic' : 'normal';
      
      return `<span style="display: inline-block; padding: 4px 8px; border-radius: 6px; background: ${fillColor}; color: ${textColor}; font-weight: ${fontWeight}; font-style: ${fontStyle}; border: 1px solid rgba(0,0,0,0.1);">${code}</span>`;
    };

    let html = `
      <table style="width: 100%; border-collapse: collapse; font-size: 12px;">
        <thead style="background-color: #f0f0f0; font-weight: 600;">
          <tr>
            <th style="border: 1px solid #ddd; padding: 8px; text-align: left;">Date</th>
            <th style="border: 1px solid #ddd; padding: 8px; text-align: left;">Old</th>
            <th style="border: 1px solid #ddd; padding: 8px; text-align: left;">New</th>
            <th style="border: 1px solid #ddd; padding: 8px; text-align: left;">Reason</th>
            <th style="border: 1px solid #ddd; padding: 8px; text-align: left;">By</th>
            <th style="border: 1px solid #ddd; padding: 8px; text-align: left;">Override</th>
          </tr>
        </thead>
        <tbody>
    `;

    records.forEach((record, index) => {
      const changedAt = new Date(record.changed_at).toLocaleDateString('en-GB', { 
        day: 'numeric', 
        month: 'short', 
        hour: '2-digit', 
        minute: '2-digit' 
      });
      const oldShift = formatShiftCode(record.old_shift_code || '—');
      const newShift = formatShiftCode(record.new_shift_code || '—');
      const reason = record.change_reason || '—';
      const changedBy = record.changed_by_name || 'System';
      
      // Show override if it applies to the period when this assignment was active
      // An assignment is active from when it was created until the next change
      let overrideInfo = '—';
      if (record.override_start_time || record.override_end_time || record.override_hours) {
        const overrideTime = record.override_created_at ? new Date(record.override_created_at).getTime() : null;
        const thisChangeTime = new Date(record.changed_at).getTime();
        
        // Get the next change time (previous index since records are DESC ordered)
        const nextChangeTime = index > 0 ? new Date(records[index - 1].changed_at).getTime() : null;
        
        // Show override if it was created during this assignment's active period
        if (overrideTime && overrideTime >= thisChangeTime && (!nextChangeTime || overrideTime < nextChangeTime)) {
          const parts = [];
          if (record.override_start_time) {
            parts.push(`${record.override_start_time.substring(0, 5)}`);
          }
          if (record.override_end_time) {
            parts.push(`${record.override_end_time.substring(0, 5)}`);
          }
          if (record.override_hours) {
            parts.push(`${record.override_hours}h`);
          }
          if (record.override_comment) {
            parts.push(`"${record.override_comment}"`);
          }
          overrideInfo = parts.join(' ');
        }
      }

      html += `
        <tr>
          <td style="border: 1px solid #ddd; padding: 6px 8px; color: #666; font-size: 11px;">${changedAt}</td>
          <td style="border: 1px solid #ddd; padding: 6px 8px; font-weight: 600; color: #333;">${oldShift}</td>
          <td style="border: 1px solid #ddd; padding: 6px 8px; font-weight: 600; color: #2563eb;">${newShift}</td>
          <td style="border: 1px solid #ddd; padding: 6px 8px; font-size: 11px; color: #666;">${reason}</td>
          <td style="border: 1px solid #ddd; padding: 6px 8px; font-size: 11px; color: #666;">${changedBy}</td>
          <td style="border: 1px solid #ddd; padding: 6px 8px; font-size: 11px; color: #f97316; font-weight: 500;">${overrideInfo}</td>
        </tr>
      `;
    });

    html += '</tbody></table>';
    return html;
  };

  return {
    init,
    loadAssignmentHistory
  };
})();

// Initialize when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => AssignmentHistoryModule.init());
} else {
  AssignmentHistoryModule.init();
}

// Expose to window for manual access
window.AssignmentHistoryModule = AssignmentHistoryModule;

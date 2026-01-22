/* =========================================================
   ENHANCED AUDIT TRAIL DISPLAY
   ========================================================= */

// Enhanced audit trail with user name resolution, date ranges, and mobile-friendly UI
// Requires: window.supabaseClient, window.currentUser, window.currentToken

const AUDIT_SECTION_ID = "audit";
let usersCache = new Map(); // Cache for user ID to name mapping

/**
 * Initialize audit trail module
 */
function initAuditTrail() {
  // Set default date range (last 7 days)
  const endDate = new Date();
  const startDate = new Date();
  startDate.setDate(startDate.getDate() - 7);
  
  document.getElementById("auditFilterStartDate").value = startDate.toISOString().split('T')[0];
  document.getElementById("auditFilterEndDate").value = endDate.toISOString().split('T')[0];
  
  // Load users for name resolution
  loadUsers();
  
  // Event listeners
  document.getElementById("auditLoadBtn")?.addEventListener("click", loadAuditLogs);
  document.getElementById("auditExportBtn")?.addEventListener("click", exportAuditLogsCSV);
  document.getElementById("auditClearFiltersBtn")?.addEventListener("click", clearFilters);
}

/**
 * Load all users for name resolution
 */
async function loadUsers() {
  try {
    const token = window.currentToken || sessionStorage.getItem("calpe_ward_token");
    if (!token) {
      throw new Error("No session token available for audit user list.");
    }
    const { data: users, error } = await window.supabaseClient.rpc("admin_get_users", {
      p_token: token,
      p_include_inactive: true
    });
    
    if (error) throw error;
    
    usersCache.clear();
    (users || []).forEach(u => {
      usersCache.set(u.id, {
        name: u.name,
        is_admin: u.is_admin,
        role_id: u.role_id
      });
    });
    
    console.log(`[AUDIT] Loaded ${usersCache.size} users for name resolution`);
  } catch (error) {
    console.error("Error loading users:", error);
  }
}

/**
 * Clear all filters and reset to defaults
 */
function clearFilters() {
  document.getElementById("auditFilterAction").value = "";
  document.getElementById("auditFilterActorUser").value = "";
  document.getElementById("auditFilterTargetUser").value = "";
  
  const endDate = new Date();
  const startDate = new Date();
  startDate.setDate(startDate.getDate() - 7);
  
  document.getElementById("auditFilterStartDate").value = startDate.toISOString().split('T')[0];
  document.getElementById("auditFilterEndDate").value = endDate.toISOString().split('T')[0];
}

/**
 * Resolve user ID to name
 */
function getUserName(userId) {
  if (!userId) return "N/A";
  const user = usersCache.get(userId);
  if (user) {
    return user.name + (user.is_admin ? " 👑" : "");
  }
  return userId.slice(0, 8) + "...";
}

/**
 * Load audit logs with filtering
 */
async function loadAuditLogs() {
  if (!window.currentUser?.is_admin) {
    alert("Admin access required");
    return;
  }

  const filterAction = document.getElementById("auditFilterAction")?.value?.trim() || null;
  const filterActorUser = document.getElementById("auditFilterActorUser")?.value?.trim() || null;
  const filterTargetUser = document.getElementById("auditFilterTargetUser")?.value?.trim() || null;
  const startDate = document.getElementById("auditFilterStartDate")?.value || null;
  const endDate = document.getElementById("auditFilterEndDate")?.value || null;

  // Calculate days back from date range
  let daysBack = 7; // default
  if (startDate) {
    const start = new Date(startDate);
    const now = new Date();
    daysBack = Math.ceil((now - start) / (1000 * 60 * 60 * 24));
  }

  try {
    // Show loading state
    document.getElementById("auditLogsTable").innerHTML = `
      <div style="padding:24px; text-align:center; color:var(--dim);">
        Loading audit logs...
      </div>
    `;

    // Use unified audit trail RPC
    const { data: logs, error } = await window.supabaseClient
      .rpc("get_unified_audit_trail", {
        p_token: window.currentToken,
        p_days_back: Math.max(daysBack, 365), // Cap at 365 days
        p_action_filter: filterAction,
        p_user_filter: filterActorUser,
        p_target_user_filter: filterTargetUser
      });

    if (error) {
      console.error("Error loading audit logs:", error);
      alert("Failed to load audit logs: " + error.message);
      return;
    }

    if (!logs || logs.length === 0) {
      document.getElementById("auditLogsTable").innerHTML = `
        <div style="padding:24px; text-align:center; color:var(--dim);">
          No audit logs found for the selected filters.
        </div>
      `;
      return;
    }

    // Filter by date range if specified
    let filteredLogs = logs;
    if (startDate || endDate) {
      filteredLogs = logs.filter(log => {
        const logDate = new Date(log.created_at);
        if (startDate && logDate < new Date(startDate + "T00:00:00")) return false;
        if (endDate && logDate > new Date(endDate + "T23:59:59")) return false;
        return true;
      });
    }

    console.log(`[AUDIT] Loaded ${filteredLogs.length} audit logs`);
    renderAuditTable(filteredLogs);
  } catch (error) {
    console.error("Error in loadAuditLogs:", error);
    alert("An error occurred while loading audit logs.");
  }
}

/**
 * Render audit logs in a mobile-friendly expandable table
 */
function renderAuditTable(logs) {
  const table = document.getElementById("auditLogsTable");

  // Create table with expandable rows
  let html = `
    <table style="width:100%; border-collapse:collapse; font-size:13px;">
      <thead style="background:#f7f9fc; border-bottom:2px solid var(--line); position:sticky; top:0; z-index:1;">
        <tr style="text-align:left;">
          <th style="padding:12px 10px; font-weight:700; color:#374151;">Timestamp</th>
          <th style="padding:12px 10px; font-weight:700; color:#374151;">Action</th>
          <th style="padding:12px 10px; font-weight:700; color:#374151;">User</th>
          <th style="padding:12px 10px; font-weight:700; color:#374151;">Target</th>
          <th style="padding:12px 10px; font-weight:700; color:#374151; text-align:center;">Status</th>
          <th style="padding:12px 10px; font-weight:700; color:#374151; text-align:center;">Details</th>
        </tr>
      </thead>
      <tbody>
  `;

  // Render rows
  logs.forEach((log, index) => {
    const timestamp = new Date(log.created_at).toLocaleString("en-GB", {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
    const action = escapeHtml(log.action || "");
    const userName = getUserName(log.user_id);
    const targetName = log.target_user_id ? getUserName(log.target_user_id) : 
                       (log.resource_id ? `Resource: ${log.resource_id.slice(0, 8)}...` : "-");
    const status = log.status === "success" ? "✓" : "✗";
    const statusColor = log.status === "success" ? "#10b981" : "#ef4444";
    const statusBg = log.status === "success" ? "#d1fae5" : "#fee2e2";

    // Build details JSON
    const details = {
      resource_type: log.resource_type,
      resource_id: log.resource_id,
      old_values: log.old_values,
      new_values: log.new_values,
      impersonator: log.impersonator_user_id ? getUserName(log.impersonator_user_id) : null,
      error: log.error_message,
      metadata: log.metadata,
      ip_hash: log.ip_hash,
      user_agent_hash: log.user_agent_hash
    };

    html += `
      <tr style="border-bottom:1px solid var(--line); cursor:pointer; transition:background 0.15s;" 
          onclick="toggleAuditDetails(${index})"
          onmouseover="this.style.background='#f9fafb'"
          onmouseout="this.style.background='#fff'">
        <td style="padding:10px; white-space:nowrap; font-size:12px;">${timestamp}</td>
        <td style="padding:10px; font-weight:600; color:#1f2937;">${action}</td>
        <td style="padding:10px; color:#4b5563;">${userName}</td>
        <td style="padding:10px; color:#6b7280; font-size:12px;">${targetName}</td>
        <td style="padding:10px; text-align:center;">
          <span style="display:inline-block; padding:4px 10px; border-radius:12px; font-weight:700; font-size:14px; background:${statusBg}; color:${statusColor};">
            ${status}
          </span>
        </td>
        <td style="padding:10px; text-align:center;">
          <button style="padding:4px 12px; border-radius:6px; border:1px solid var(--line); background:#fff; cursor:pointer; font-size:12px; color:#3b82f6; font-weight:600;"
                  onclick="event.stopPropagation(); toggleAuditDetails(${index})">
            <span id="audit-toggle-${index}">▼</span>
          </button>
        </td>
      </tr>
      <tr id="audit-details-${index}" style="display:none; background:#f9fafb;">
        <td colspan="6" style="padding:16px; border-bottom:2px solid var(--line);">
          <div style="display:grid; grid-template-columns:repeat(auto-fit, minmax(200px, 1fr)); gap:12px; font-size:12px;">
            ${details.resource_type ? `
              <div>
                <strong style="color:#6b7280;">Resource Type:</strong>
                <div style="margin-top:4px; color:#1f2937;">${escapeHtml(details.resource_type)}</div>
              </div>
            ` : ''}
            ${details.resource_id ? `
              <div>
                <strong style="color:#6b7280;">Resource ID:</strong>
                <div style="margin-top:4px; font-family:monospace; font-size:11px; color:#1f2937;">${escapeHtml(details.resource_id)}</div>
              </div>
            ` : ''}
            ${details.impersonator ? `
              <div>
                <strong style="color:#ef4444;">⚠ Impersonator:</strong>
                <div style="margin-top:4px; color:#1f2937;">${details.impersonator}</div>
              </div>
            ` : ''}
            ${details.error ? `
              <div style="grid-column:1/-1;">
                <strong style="color:#ef4444;">Error:</strong>
                <pre style="margin-top:4px; padding:8px; background:#fee2e2; border-radius:6px; overflow-x:auto; color:#991b1b; font-size:11px;">${escapeHtml(details.error)}</pre>
              </div>
            ` : ''}
          </div>
          ${details.old_values || details.new_values ? `
            <div style="margin-top:12px; display:grid; grid-template-columns:1fr 1fr; gap:12px;">
              ${details.old_values ? `
                <div>
                  <strong style="color:#6b7280; font-size:12px;">Old Values:</strong>
                  <pre style="margin-top:6px; padding:10px; background:#fff; border:1px solid var(--line); border-radius:6px; overflow-x:auto; font-size:11px; max-height:200px;">${JSON.stringify(details.old_values, null, 2)}</pre>
                </div>
              ` : ''}
              ${details.new_values ? `
                <div>
                  <strong style="color:#6b7280; font-size:12px;">New Values:</strong>
                  <pre style="margin-top:6px; padding:10px; background:#fff; border:1px solid var(--line); border-radius:6px; overflow-x:auto; font-size:11px; max-height:200px;">${JSON.stringify(details.new_values, null, 2)}</pre>
                </div>
              ` : ''}
            </div>
          ` : ''}
          ${details.metadata ? `
            <div style="margin-top:12px;">
              <strong style="color:#6b7280; font-size:12px;">Metadata:</strong>
              <pre style="margin-top:6px; padding:10px; background:#fff; border:1px solid var(--line); border-radius:6px; overflow-x:auto; font-size:11px; max-height:200px;">${JSON.stringify(details.metadata, null, 2)}</pre>
            </div>
          ` : ''}
        </td>
      </tr>
    `;
  });

  html += `
      </tbody>
    </table>
  `;

  table.innerHTML = html;
}

/**
 * Toggle expandable details row
 */
function toggleAuditDetails(index) {
  const detailsRow = document.getElementById(`audit-details-${index}`);
  const toggle = document.getElementById(`audit-toggle-${index}`);
  
  if (detailsRow.style.display === "none") {
    detailsRow.style.display = "table-row";
    toggle.textContent = "▲";
  } else {
    detailsRow.style.display = "none";
    toggle.textContent = "▼";
  }
}

/**
 * Export audit logs to CSV
 */
async function exportAuditLogsCSV() {
  if (!window.currentUser?.is_admin) {
    alert("Admin access required");
    return;
  }

  try {
    const startDate = document.getElementById("auditFilterStartDate")?.value;
    const endDate = document.getElementById("auditFilterEndDate")?.value;

    if (!startDate || !endDate) {
      alert("Please select a date range first");
      return;
    }

    const daysBack = Math.ceil((new Date() - new Date(startDate + "T00:00:00")) / (1000 * 60 * 60 * 24));
    const { data: logs, error } = await window.supabaseClient
      .rpc("get_unified_audit_trail", {
        p_token: window.currentToken,
        p_days_back: Math.max(daysBack, 365),
        p_action_filter: null,
        p_user_filter: null,
        p_target_user_filter: null
      });

    if (error) throw error;

    // Build CSV with name resolution
    const headers = ["Timestamp", "Action", "User", "Target User", "Resource Type", "Status", "Details"];
    const rows = logs.map((log) => [
      new Date(log.created_at).toLocaleString("en-GB"),
      log.action || "",
      getUserName(log.user_id),
      log.target_user_id ? getUserName(log.target_user_id) : "",
      log.resource_type || "",
      log.status || "",
      JSON.stringify(log.metadata || {})
    ]);

    const csv = [headers, ...rows].map(row => row.map(escapeCSV).join(",")).join("\n");

    // Trigger download
    const blob = new Blob([csv], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `audit_logs_${startDate}_to_${endDate}.csv`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);

    alert(`Exported ${logs.length} audit logs to CSV`);
  } catch (error) {
    console.error("Error exporting audit logs:", error);
    alert("Failed to export: " + error.message);
  }
}

/**
 * Escape HTML to prevent XSS
 */
function escapeHtml(text) {
  if (!text) return "";
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}

/**
 * Escape CSV field
 */
function escapeCSV(field) {
  if (field == null) return "";
  field = String(field);
  if (field.includes(",") || field.includes('"') || field.includes("\n")) {
    return `"${field.replace(/"/g, '""')}"`;
  }
  return field;
}

// Initialize when DOM is ready
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initAuditTrail);
} else {
  initAuditTrail();
}

// Expose functions globally
window.toggleAuditDetails = toggleAuditDetails;
window.loadAuditLogs = loadAuditLogs;
window.exportAuditLogsCSV = exportAuditLogsCSV;

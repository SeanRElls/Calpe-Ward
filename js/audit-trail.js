/* =========================================================
   SUPERADMIN AUDIT TRAIL DISPLAY
   ========================================================= */

// Superadmin-only audit trail viewer for admin.html
// Requires: window.supabaseClient, window.currentUser, window.currentToken

const AUDIT_SECTION_ID = "audit";

async function loadAuditLogs() {
  if (!window.currentUser?.is_admin) {
    alert("Admin access required");
    return;
  }

  const filterAction = document.getElementById("auditFilterAction")?.value?.trim() || null;
  const filterUser = document.getElementById("auditFilterUser")?.value?.trim() || null;
  const daysBack = parseInt(document.getElementById("auditFilterDays")?.value || "7");

  try {
    // Use unified audit trail RPC that combines audit_logs and rota_assignment_history
    const { data: logs, error } = await window.supabaseClient
      .rpc("get_unified_audit_trail", {
        p_token: window.currentToken,
        p_days_back: daysBack,
        p_action_filter: filterAction,
        p_user_filter: filterUser
      });

    if (error) {
      console.error("Error loading audit logs:", error);
      alert("Failed to load audit logs: " + error.message);
      return;
    }

    if (!logs || logs.length === 0) {
      document.getElementById("auditLogsTable").innerHTML = `
        <div style="padding:24px; text-align:center; color:var(--muted);">
          No audit logs found for the selected filters.
        </div>
      `;
      return;
    }

    // Render table
    renderAuditTable(logs, filterUser);
  } catch (err) {
    console.error(err);
    alert("Error: " + err.message);
  }
}

function renderAuditTable(logs, filterUser) {
  const table = document.getElementById("auditLogsTable");

  // Create table header
  let html = `
    <table style="width:100%; border-collapse:collapse; font-size:12px;">
      <thead style="background:#f7f9fc; border-bottom:1px solid var(--line);">
        <tr style="text-align:left;">
          <th style="padding:10px; font-weight:700;">Timestamp</th>
          <th style="padding:10px; font-weight:700;">Action</th>
          <th style="padding:10px; font-weight:700;">User</th>
          <th style="padding:10px; font-weight:700;">Target/Resource</th>
          <th style="padding:10px; font-weight:700;">Status</th>
          <th style="padding:10px; font-weight:700;">Details</th>
        </tr>
      </thead>
      <tbody>
  `;

  // Filter and render rows
  logs.forEach((log) => {
    // Skip if filterUser doesn't match
    if (filterUser && !log.user_id?.toLowerCase().includes(filterUser.toLowerCase())) {
      return;
    }

    const timestamp = new Date(log.created_at).toLocaleString("en-GB");
    const action = escapeHtml(log.action || "");
    const userId = log.user_id ? log.user_id.slice(0, 8) + "..." : "N/A";
    const targetUser = log.target_user_id ? log.target_user_id.slice(0, 8) + "..." : (log.resource_id ? log.resource_id.slice(0, 8) + "..." : "-");
    const status = log.status === "success" ? "✓" : "✗";
    const statusColor = log.status === "success" ? "#28a745" : "#dc3545";

    // Build details JSON
    const details = {
      resource_type: log.resource_type,
      impersonator: log.impersonator_user_id ? log.impersonator_user_id.slice(0, 8) + "..." : null,
      error: log.error_message,
      metadata: log.metadata
    };

    const detailsStr = JSON.stringify(details).replace(/"/g, "&quot;");

    html += `
      <tr style="border-bottom:1px solid var(--line);">
        <td style="padding:10px; white-space:nowrap;">${timestamp}</td>
        <td style="padding:10px; font-weight:600;">${action}</td>
        <td style="padding:10px; font-family:monospace; font-size:11px;">${userId}</td>
        <td style="padding:10px; font-family:monospace; font-size:11px;">${targetUser}</td>
        <td style="padding:10px; color:${statusColor}; font-weight:700;">${status}</td>
        <td style="padding:10px;">
          <button class="btn" style="font-size:11px; padding:4px 8px;" onclick="showAuditDetails('${detailsStr}')">View</button>
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

function showAuditDetails(detailsStr) {
  const details = JSON.parse(detailsStr.replace(/&quot;/g, '"'));
  const modal = document.createElement("div");
  modal.style.cssText = `
    position: fixed; top: 0; left: 0; right: 0; bottom: 0;
    background: rgba(0,0,0,0.5); display: flex; align-items: center;
    justify-content: center; z-index: 10002;
  `;

  modal.innerHTML = `
    <div style="
      background: white; padding: 24px; border-radius: 8px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.3); max-width: 500px;
      max-height: 80vh; overflow-y: auto;
    ">
      <h3 style="margin: 0 0 12px 0; color: #333;">Audit Event Details</h3>
      <pre style="
        background: #f5f5f5; padding: 12px; border-radius: 4px;
        font-size: 11px; overflow-x: auto; margin: 0;
      ">${JSON.stringify(details, null, 2)}</pre>
      <button onclick="this.closest('div').parentElement.remove()" class="btn primary" style="
        margin-top: 12px; width: 100%;
      ">Close</button>
    </div>
  `;

  document.body.appendChild(modal);
}

async function exportAuditLogsCSV() {
  if (!window.currentUser?.is_admin) {
    alert("Admin access required");
    return;
  }

  try {
    const daysBack = parseInt(document.getElementById("auditFilterDays")?.value || "7");
    const endDate = new Date();
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - daysBack);

    const { data: logs, error } = await window.supabaseClient
      .rpc("get_unified_audit_trail", {
        p_token: window.currentToken,
        p_days_back: daysBack,
        p_action_filter: null,
        p_user_filter: null
      });

    if (error) throw error;

    // Build CSV
    const headers = ["Timestamp", "Action", "User ID", "Target User ID", "Resource Type", "Status", "Details"];
    const rows = logs.map((log) => [
      new Date(log.created_at).toLocaleString("en-GB"),
      log.action || "",
      log.user_id || "",
      log.target_user_id || "",
      log.resource_type || "",
      log.status || "",
      JSON.stringify(log.metadata || {}).replace(/"/g, '""')
    ]);

    let csv = headers.join(",") + "\n";
    rows.forEach((row) => {
      csv += row.map((cell) => `"${cell}"`).join(",") + "\n";
    });

    // Trigger download
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
    const link = document.createElement("a");
    const url = URL.createObjectURL(blob);
    link.setAttribute("href", url);
    link.setAttribute("download", `audit_logs_${new Date().toISOString().slice(0, 10)}.csv`);
    link.style.visibility = "hidden";
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);

    alert("Audit logs exported successfully!");
  } catch (err) {
    console.error(err);
    alert("Export failed: " + err.message);
  }
}

function escapeHtml(str) {
  return String(str || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

// Initialize when DOM is ready
document.addEventListener("DOMContentLoaded", () => {
  const loadBtn = document.getElementById("auditLoadBtn");
  const exportBtn = document.getElementById("auditExportBtn");

  if (loadBtn) loadBtn.addEventListener("click", loadAuditLogs);
  if (exportBtn) exportBtn.addEventListener("click", exportAuditLogsCSV);
});

// Expose to window for global use
window.loadAuditLogs = loadAuditLogs;
window.exportAuditLogsCSV = exportAuditLogsCSV;
window.showAuditDetails = showAuditDetails;

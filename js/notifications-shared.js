// ============================================
// NOTIFICATION FORMATTING FUNCTIONS
// ============================================

/**
 * Get the formatted title for a notification
 * @param {Object} n - Notification object with type and payload
 * @returns {string} Formatted title with emoji
 */
function getNotificationTitle(n){
  let payload = n?.payload || {};
  if (typeof payload === 'string') {
    try {
      payload = JSON.parse(payload);
    } catch(e) {
      console.error('[NOTIF TITLE PARSE ERROR]', e, 'raw payload:', payload);
      payload = {};
    }
  }
  
  // Leave request notification
  if (n.type === "leave_request") {
    return `🏖️ Leave Request from ${payload?.staff_name || "Staff Member"}`;
  }
  
  // Special handling for swap_request type
  if (n.type === "swap_request") {
    // Check if this is a staff swap request or admin approval notification
    if (payload?.notification_type === "swap_accepted") {
      return `⏳ Swap Pending Approval`;
    }
    const initiatorName = payload?.initiator_name || "Unknown";
    return `📬 Shift Swap Request from ${initiatorName}`;
  }
  
  // Special handling for swap_approved type
  if (n.type === "swap_approved") {
    return `✅ Swap Approved`;
  }
  
  // Special handling for swap_pending type (admin notification)
  if (n.type === "swap_pending") {
    return `🔔 New Swap Request Pending`;
  }
  
  return escapeHtml(
    payload.title || n.title || n.type || "Notification"
  );
}

/**
 * Get the formatted body for a notification
 * @param {Object} n - Notification object with type and payload
 * @returns {string} Formatted body text (HTML safe)
 */
function getNotificationBody(n){
  let payload = n?.payload || {};
  if (typeof payload === 'string') {
    try {
      payload = JSON.parse(payload);
    } catch(e) {
      console.error('Failed to parse notification payload:', e);
      payload = {};
    }
  }
  
  // Leave request notification
  if (n.type === "leave_request") {
    const weekStart = payload.week_start ? new Date(payload.week_start).toLocaleDateString("en-GB") : "Unknown";
    const weekEnd = payload.week_end ? new Date(payload.week_end).toLocaleDateString("en-GB") : "Unknown";
    return `${payload?.staff_name || "Staff member"} has requested annual leave for the week of ${weekStart} - ${weekEnd}. Review and approve in Leave Requests.`;
  }
  
  // Special handling for swap_request type
  if (n.type === "swap_request") {
    // Check if this is admin approval notification (swap was accepted by counterparty)
    if (payload?.notification_type === "swap_accepted") {
      const initiatorDate = payload.initiator_date ? new Date(payload.initiator_date).toLocaleDateString("en-GB") : "Unknown";
      const counterpartyDate = payload.counterparty_date ? new Date(payload.counterparty_date).toLocaleDateString("en-GB") : "Unknown";
      return `${payload.initiator_name || "Unknown"} and ${payload.counterparty_name || "Unknown"} have agreed to swap their shifts. ${payload.initiator_name} will work ${payload.counterparty_shift_code} on ${counterpartyDate}, and ${payload.counterparty_name} will work ${payload.initiator_shift_code} on ${initiatorDate}. Please approve to proceed.`;
    }
    // Standard staff request to counterparty
    const initiatorDate = payload.initiator_date ? new Date(payload.initiator_date).toLocaleDateString("en-GB") : "Unknown";
    const counterpartyDate = payload.counterparty_date ? new Date(payload.counterparty_date).toLocaleDateString("en-GB") : "Unknown";
    return `${payload.initiator_name || "Unknown"} wants to swap their shift on ${initiatorDate} with your shift on ${counterpartyDate}. Please accept or decline the request.`;
  }
  
  // Special handling for swap_approved type
  if (n.type === "swap_approved") {
    const counterpartyDate = payload.counterparty_date ? new Date(payload.counterparty_date).toLocaleDateString("en-GB") : "Unknown";
    const initiatorDate = payload.initiator_date ? new Date(payload.initiator_date).toLocaleDateString("en-GB") : "Unknown";
    const approvedBy = payload.approved_by || "Admin";
    return `Your swap with ${payload.counterparty_name || "Unknown"} has been approved. You now have a shift on ${counterpartyDate}. Approved by: ${approvedBy}`;
  }
  
  // Special handling for swap_pending type (admin notification)
  if (n.type === "swap_pending") {
    const initiatorDate = payload.initiator_date ? new Date(payload.initiator_date).toLocaleDateString("en-GB") : "Unknown";
    const counterpartyDate = payload.counterparty_date ? new Date(payload.counterparty_date).toLocaleDateString("en-GB") : "Unknown";
    return `${payload.initiator_name || "Unknown"} wants to swap their ${initiatorDate} shift with ${payload.counterparty_name || "Unknown"}'s ${counterpartyDate} shift. Click Shift Swaps to review.`;
  }
  
  const body = payload.body || payload.message || payload.text || "";

  if (typeof body === "string" && body.trim()) return escapeHtml(body);
  try {
    return escapeHtml(JSON.stringify(payload));
  } catch (e) {
    return "";
  }
}

// ============================================
// NOTICE FORMATTING FUNCTIONS
// ============================================

function getNoticeBody(n) {
  const lang = (typeof currentLang !== "undefined" && currentLang === "es") ? "es" : "en";
  const bodyEs = n?.body_es;
  const bodyEn = n?.body_en;
  const bodyHtml = n?.body_html;

  if (lang === "es" && typeof bodyEs === "string" && bodyEs.trim()) return bodyEs;
  if (typeof bodyEn === "string" && bodyEn.trim()) return bodyEn;
  if (typeof bodyHtml === "string" && bodyHtml.trim()) return bodyHtml;

  const body = n?.body || "";
  return typeof body === "string" ? escapeHtml(body) : "";
}

// ============================================
// HTML RENDERING FUNCTIONS
// ============================================

function renderNotificationCard(item) {
  const pill = item.status === "pending"
    ? `<span class="notice-pill unread">New</span>`
    : `<span class="notice-pill">${escapeHtml(item.status)}</span>`;

  let actionHtml = '';
  if (item.status === "pending" && item.requiresAction) {
    // Leave request notification (admin only) - just acknowledge, they add manually
    if (item.data?.type === "leave_request") {
      actionHtml = `<div class="notification-actions">
        <button type="button" class="primary" data-notif-ack="${item.id}">Got it</button>
        <button type="button" data-notif-ignore="${item.id}">Ignore</button>
      </div>`;
    }
    // Check if this is a swap_pending notification (for admins)
    else if (item.data?.type === "swap_pending") {
      actionHtml = `<div class="notification-actions">
        <button type="button" class="primary" data-admin-approve-swap="${item.id}">Approve</button>
        <button type="button" data-admin-decline-swap="${item.id}">Decline</button>
      </div>`;
    } else {
      // swap_request or other actionable notifications
      actionHtml = `<div class="notification-actions">
        <button type="button" class="primary" data-notif-accept="${item.id}">Accept</button>
        <button type="button" data-notif-decline="${item.id}">Decline</button>
        <button type="button" data-notif-ignore="${item.id}">Ignore</button>
      </div>`;
    }
  } else if (item.status === "pending" && !item.requiresAction) {
    actionHtml = `<div class="notification-actions">
      <button type="button" class="primary" data-notif-ack="${item.id}">Acknowledge</button>
      <button type="button" data-notif-ignore="${item.id}">Ignore</button>
    </div>`;
  }

  return `<details class="notification-card">
    <summary>
      <div style="flex:1; min-width:0;">
        <div style="color:#333; margin-bottom:4px;">${escapeHtml(item.title)}</div>
        <div style="font-size:0.85em; color:#999;">${escapeHtml(item.when || '')}</div>
      </div>
      <div>${pill}</div>
    </summary>
    <div class="notification-body">
      <div style="margin-bottom:12px; line-height:1.6; color:#555;">${item.body}</div>
      ${actionHtml}
    </div>
  </details>`;
}

function renderNoticeCard(item) {
  const pill = item.acked
    ? `<span class="notice-pill">Acknowledged</span>`
    : `<span class="notice-pill unread">New</span>`;

  let actionHtml = '';
  if (!item.acked) {
    actionHtml = `<div class="notice-actions">
      <button type="button" class="primary" data-ack="${item.id}">Acknowledge</button>
    </div>`;
  }

  return `<details class="notice-card">
    <summary>
      <div style="flex:1; min-width:0;">
        <div style="color:#333; margin-bottom:4px;">${escapeHtml(item.title)}</div>
        <div style="font-size:0.85em; color:#999;">By ${escapeHtml(item.who)} · ${escapeHtml(item.when || '')}</div>
      </div>
      <div>${pill}</div>
    </summary>
    <div class="notification-body">
      <div style="margin-bottom:12px; line-height:1.6; color:#555;">${item.body}</div>
      ${actionHtml}
    </div>
  </details>`;
}

function renderAllNoticesAndNotifications(notices, notifications) {
  let html = '';
  
  if (notifications && notifications.length > 0) {
    html += '<div style="margin-bottom:20px;"><h3 style="margin:0 0 12px 0; color:#333; font-size:1em; font-weight:600;">📬 Notifications</h3>';
    html += notifications.map(n => renderNotificationCard(n)).join('');
    html += '</div>';
  }
  
  if (notices && notices.length > 0) {
    html += '<div><h3 style="margin:0 0 12px 0; color:#333; font-size:1em; font-weight:600;">📋 Notices</h3>';
    html += notices.map(n => renderNoticeCard(n)).join('');
    html += '</div>';
  }
  
  if (!html) {
    html = '<div style="text-align:center; padding:20px; color:#999;">No notices or notifications</div>';
  }
  
  return html;
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    getNotificationTitle,
    getNotificationBody,
    getNoticeBody,
    renderNotificationCard,
    renderNoticeCard,
    renderAllNoticesAndNotifications
  };
}

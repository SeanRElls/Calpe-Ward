/**
 * Admin Status Dashboard
 * Real-time metrics and quick actions for the admin panel
 */

let statusDashboardData = {
  period: null,
  prevPeriod: null,
  draftStatus: null,
  swapRequests: 0,
  timeoffRequests: 0,
  staffCount: 0,
  coverage: 0,
  understaffedDays: [], // Days not meeting minimum staffing
  prevCoverage: 0,
  prevStaffCount: 0
};

function getDashboardToken() {
  const token = window.currentToken || sessionStorage.getItem("calpe_ward_token");
  if (!token) {
    throw new Error("No session token available for admin dashboard.");
  }
  return token;
}

async function fetchRotaPeriods() {
  const token = getDashboardToken();
  const { data, error } = await window.supabaseClient.rpc("rpc_get_rota_periods", {
    p_token: token
  });
  if (error) throw error;
  const periods = Array.isArray(data) ? data.slice() : [];
  periods.sort((a, b) => new Date(a.start_date) - new Date(b.start_date));
  return periods;
}

/**
 * Initialize the status dashboard
 */
function initStatusDashboard() {
  console.log("[STATUS-DASHBOARD] Initializing");
  
  // Load data periodically
  loadStatusDashboardData();
  setInterval(loadStatusDashboardData, 30000); // Refresh every 30 seconds
  
  // Quick action buttons
  document.getElementById("quickPublishBtn")?.addEventListener("click", () => {
    document.querySelector('[data-panel="rota-periods"]')?.click();
  });
  
  document.getElementById("quickSwapsBtn")?.addEventListener("click", () => {
    document.querySelector('[data-panel="shift-swaps"]')?.click();
  });
  
  document.getElementById("quickTimeoffBtn")?.addEventListener("click", () => {
    document.querySelector('[data-panel="shift-swaps"]')?.click();
  });
  
  // Previous period toggle
  document.getElementById("prevPeriodToggle")?.addEventListener("click", () => {
    const content = document.getElementById("prevPeriodContent");
    const icon = document.getElementById("prevPeriodToggleIcon");
    const isHidden = content.style.display === "none";
    content.style.display = isHidden ? "block" : "none";
    icon.style.transform = isHidden ? "rotate(90deg)" : "rotate(0deg)";
  });
}

/**
 * Load all dashboard data
 */
async function loadStatusDashboardData() {
  try {
    // Fetch current period info
    await loadPeriodInfo();
    
    // Fetch previous period info
    await loadPreviousPeriodInfo();
    
    // Fetch request counts
    await loadRequestCounts();
    
    // Fetch staffing info
    await loadStaffingInfo();
    
    // Check for understaffed days
    await checkUnderstaffedDays();
    
    // Render dashboard
    renderStatusDashboard();
    renderPreviousPeriodDashboard();
    
  } catch (error) {
    console.error("[STATUS-DASHBOARD] Error loading data:", error);
  }
}

/**
 * Load current period info
 */
async function loadPeriodInfo() {
  try {
    const periods = await fetchRotaPeriods();
    statusDashboardData.period = periods.length ? periods[periods.length - 1] : null;
    statusDashboardData._periodsCache = periods;
  } catch (error) {
    console.error("[STATUS-DASHBOARD] Error loading period:", error);
  }
}

/**
 * Load previous period info
 */
async function loadPreviousPeriodInfo() {
  try {
    const periods = statusDashboardData._periodsCache || await fetchRotaPeriods();
    statusDashboardData.prevPeriod = periods.length > 1 ? periods[periods.length - 2] : null;
    
    // Load staffing data for previous period
    if (statusDashboardData.prevPeriod?.id) {
      const token = getDashboardToken();
      const { data: staff, error: staffError } = await window.supabaseClient.rpc("admin_get_users", {
        p_token: token,
        p_include_inactive: true
      });
      if (staffError) throw staffError;
      const activeStaff = Array.isArray(staff) ? staff.filter(u => u.is_active) : [];
      statusDashboardData.prevStaffCount = activeStaff.length;

      const { data: assignments, error: assignError } = await window.supabaseClient.rpc("rpc_get_rota_assignments", {
        p_token: token,
        p_period_id: statusDashboardData.prevPeriod.id,
        p_include_draft: true
      });
      if (assignError) throw assignError;
      const assignCount = Array.isArray(assignments) ? assignments.length : 0;
      
      if (statusDashboardData.prevStaffCount > 0) {
        const expectedAssignments = statusDashboardData.prevStaffCount * 30;
        statusDashboardData.prevCoverage = Math.min(
          100,
          Math.round((assignCount || 0) / expectedAssignments * 100)
        );
      }
    }
  } catch (error) {
    console.error("[STATUS-DASHBOARD] Error loading previous period:", error);
  }
}

/**
 * Load request counts
 */
async function loadRequestCounts() {
  try {
    if (!statusDashboardData.period?.id) return;
    
    const token = getDashboardToken();
    const { data: swaps, error: swapError } = await window.supabaseClient.rpc("admin_get_swap_requests", {
      p_token: token
    });
    if (swapError) throw swapError;

    const swapRows = Array.isArray(swaps) ? swaps : [];
    const pendingSwaps = swapRows.filter(
      s => s.period_id === statusDashboardData.period.id && s.status === "pending"
    );
    statusDashboardData.swapRequests = pendingSwaps.length;

    const pendingTimeoff = pendingSwaps.filter(s => (s.initiator_shift_code || "").startsWith("O"));
    statusDashboardData.timeoffRequests = pendingTimeoff.length;
    
  } catch (error) {
    console.error("[STATUS-DASHBOARD] Error loading request counts:", error);
  }
}

/**
 * Load staffing info
 */
async function loadStaffingInfo() {
  try {
    if (!statusDashboardData.period?.id) return;
    
    // Total active staff
    const token = getDashboardToken();
    const { data: staff, error: staffError } = await window.supabaseClient.rpc("admin_get_users", {
      p_token: token,
      p_include_inactive: true
    });
    if (staffError) throw staffError;
    const activeStaff = Array.isArray(staff) ? staff.filter(u => u.is_active) : [];
    statusDashboardData.staffCount = activeStaff.length;
    
    // Calculate coverage percentage - query published shifts instead
    // Since rota_assignments doesn't have period_id directly
    const { data: assignments, error: assignError } = await window.supabaseClient.rpc("rpc_get_rota_assignments", {
      p_token: token,
      p_period_id: statusDashboardData.period.id,
      p_include_draft: true
    });
    if (assignError) throw assignError;

    const assignCount = Array.isArray(assignments) ? assignments.length : 0;
    if (statusDashboardData.staffCount > 0) {
      const expectedAssignments = statusDashboardData.staffCount * 30; // rough estimate for 30-day period
      statusDashboardData.coverage = Math.min(
        100,
        Math.round((assignCount || 0) / expectedAssignments * 100)
      );
    }
    
  } catch (error) {
    console.error("[STATUS-DASHBOARD] Error loading staffing info:", error);
  }
}

/**
 * Check for days not meeting minimum staffing requirements (published periods only)
 */
async function checkUnderstaffedDays() {
  try {
    if (!statusDashboardData.period?.id) {
      statusDashboardData.understaffedDays = [];
      return;
    }
    
    // Only check published periods
    if (!statusDashboardData.period.published_at) {
      statusDashboardData.understaffedDays = [];
      return;
    }
    
    // Get staffing requirements for this period
    const token = getDashboardToken();
    const { data: requirements, error: reqError } = await window.supabaseClient.rpc("admin_get_staffing_requirements", {
      p_token: token,
      p_period_id: statusDashboardData.period.id
    });
    
    if (reqError || !requirements || requirements.length === 0) {
      console.log("[STATUS-DASHBOARD] No staffing requirements found");
      statusDashboardData.understaffedDays = [];
      return;
    }
    
    console.log("[STATUS-DASHBOARD] Found " + requirements.length + " days with requirements");
    
    // Get actual assignments for this period
    const { data: assignments, error: assignError } = await window.supabaseClient.rpc("rpc_get_rota_assignments", {
      p_token: token,
      p_period_id: statusDashboardData.period.id,
      p_include_draft: false
    });
    
    if (assignError || !assignments) {
      console.warn("[STATUS-DASHBOARD] Error fetching assignments:", assignError);
      statusDashboardData.understaffedDays = [];
      return;
    }
    
    console.log("[STATUS-DASHBOARD] Found " + assignments.length + " assignments");
    
    // Count assignments per date and shift type
    const staffingByDay = {};
    assignments.forEach(a => {
      if (!staffingByDay[a.date]) {
        staffingByDay[a.date] = { day_sn: 0, day_na: 0, night_sn: 0, night_na: 0 };
      }
      
      // Try to match shift codes/labels to staffing types
      const code = (a.shift_code || "").toUpperCase();
      const label = (a.shift_label || "").toUpperCase();
      const combined = code + " " + label;
      
      // Match by code/label patterns
      if (combined.includes("NIGHT") || combined.includes("N") || code === "N") {
        if (combined.includes("SN") || combined.includes("STAFF NURSE")) staffingByDay[a.date].night_sn++;
        else if (combined.includes("NA") || combined.includes("NURSING ASSISTANT")) staffingByDay[a.date].night_na++;
        else staffingByDay[a.date].night_sn++; // Default to SN for night shifts
      } else if (combined.includes("DAY") || combined.includes("D") || code === "D") {
        if (combined.includes("SN") || combined.includes("STAFF NURSE")) staffingByDay[a.date].day_sn++;
        else if (combined.includes("NA") || combined.includes("NURSING ASSISTANT")) staffingByDay[a.date].day_na++;
        else staffingByDay[a.date].day_sn++; // Default to SN for day shifts
      }
    });
    
    console.log("[STATUS-DASHBOARD] Staffing by day:", Object.keys(staffingByDay).length, "days");
    
    // Compare actual vs required
    const understaffed = [];
    requirements.forEach(req => {
      const actual = staffingByDay[req.date] || { day_sn: 0, day_na: 0, night_sn: 0, night_na: 0 };
      
      const daySnShort = actual.day_sn < req.day_sn_required;
      const dayNaShort = actual.day_na < req.day_na_required;
      const nightSnShort = actual.night_sn < req.night_sn_required;
      const nightNaShort = actual.night_na < req.night_na_required;
      
      if (daySnShort || dayNaShort || nightSnShort || nightNaShort) {
        const dateObj = new Date(req.date + "T00:00:00");
        const dateStr = dateObj.toLocaleDateString("en-GB", { month: "short", day: "numeric" });
        understaffed.push(dateStr);
      }
    });
    
    statusDashboardData.understaffedDays = understaffed;
    console.log("[STATUS-DASHBOARD] Understaffed days:", understaffed.length, understaffed.slice(0, 5));
    
  } catch (error) {
    console.error("[STATUS-DASHBOARD] Error checking understaffed days:", error);
    statusDashboardData.understaffedDays = [];
  }
}

/**
 * Render the status dashboard
 */
function renderStatusDashboard() {
  const period = statusDashboardData.period;
  
  // Period info
  if (period) {
    const startDate = new Date(period.start_date).toLocaleDateString("en-GB");
    const endDate = new Date(period.end_date).toLocaleDateString("en-GB");
    document.getElementById("statusPeriodText").textContent = `${startDate} – ${endDate}`;
    
    // Calculate progress
    const start = new Date(period.start_date);
    const end = new Date(period.end_date);
    const now = new Date();
    const total = end - start;
    const elapsed = now - start;
    const progress = Math.min(100, Math.max(0, Math.round(elapsed / total * 100)));
    
    const progressBar = document.querySelector("#statusPeriodProgress div");
    if (progressBar) progressBar.style.width = progress + "%";
  }
  
  // Draft status badge
  const draftBadge = document.getElementById("draftBadge");
  if (period) {
    if (period.published_at) {
      draftBadge.textContent = "Published";
      draftBadge.style.background = "#d4edda";
      draftBadge.style.color = "#155724";
    } else {
      draftBadge.textContent = period.status || "Draft";
      draftBadge.style.background = "#fff3cd";
      draftBadge.style.color = "#856404";
    }
  }
  
  // Requests window - calculate days until close
  // Assuming requests close at period end or 7 days before
  if (period) {
    const endDate = new Date(period.end_date);
    const now = new Date();
    const daysLeft = Math.ceil((endDate - now) / (1000 * 60 * 60 * 24));
    
    document.getElementById("statusRequestsText").textContent = endDate.toLocaleDateString("en-GB");
    document.getElementById("daysUntilClose").textContent = Math.max(0, daysLeft);
    
    // Color code based on urgency
    const daysElement = document.getElementById("daysUntilClose");
    if (daysLeft <= 3) {
      daysElement.style.color = "#e74c3c";
      daysElement.style.fontWeight = "700";
    } else if (daysLeft <= 7) {
      daysElement.style.color = "#f39c12";
    } else {
      daysElement.style.color = "#27ae60";
    }
  }
  
  // Coverage
  document.getElementById("statusCoverageText").textContent = statusDashboardData.coverage + "%";
  const coverageBar = document.getElementById("coverageBar");
  if (coverageBar) {
    coverageBar.style.width = statusDashboardData.coverage + "%";
    // Color code
    if (statusDashboardData.coverage < 70) {
      coverageBar.style.background = "#e74c3c";
    } else if (statusDashboardData.coverage < 90) {
      coverageBar.style.background = "#f39c12";
    } else {
      coverageBar.style.background = "#27ae60";
    }
  }
  
  // Update counts
  document.getElementById("swapCount").textContent = statusDashboardData.swapRequests;
  document.getElementById("timeoffCount").textContent = statusDashboardData.timeoffRequests;
  document.getElementById("staffCount").textContent = statusDashboardData.staffCount;
  
  // Show alerts section if there are any alerts
  updateAlerts();
}

/**
 * Render the previous period dashboard
 */
function renderPreviousPeriodDashboard() {
  const prevPeriod = statusDashboardData.prevPeriod;
  
  if (!prevPeriod) {
    document.getElementById("prevPeriodText").textContent = "No previous period";
    return;
  }
  
  // Period info
  const startDate = new Date(prevPeriod.start_date).toLocaleDateString("en-GB");
  const endDate = new Date(prevPeriod.end_date).toLocaleDateString("en-GB");
  document.getElementById("prevPeriodText").textContent = `${startDate} – ${endDate}`;
  
  // Status badge
  const prevDraftBadge = document.getElementById("prevDraftBadge");
  if (prevPeriod.published_at) {
    prevDraftBadge.textContent = "Published";
    prevDraftBadge.style.background = "#d4edda";
    prevDraftBadge.style.color = "#155724";
  } else {
    prevDraftBadge.textContent = prevPeriod.status || "Draft";
    prevDraftBadge.style.background = "#fff3cd";
    prevDraftBadge.style.color = "#856404";
  }
  
  // Coverage
  document.getElementById("prevCoverageText").textContent = statusDashboardData.prevCoverage + "%";
  
  // Staff count
  document.getElementById("prevStaffCount").textContent = statusDashboardData.prevStaffCount;
  
  // Completed status (if end date is in the past)
  const endDateObj = new Date(prevPeriod.end_date);
  const now = new Date();
  const isCompleted = endDateObj < now;
  document.getElementById("prevCompletedText").textContent = isCompleted ? "✓ Yes" : "In progress";
  if (!isCompleted) {
    document.getElementById("prevCompletedText").style.color = "#f39c12";
  }
}

/**
 * Update alerts based on current status
 */
function updateAlerts() {
  const alerts = [];
  
  // Coverage alert
  if (statusDashboardData.coverage < 80) {
    alerts.push({
      type: "warning",
      text: `Low coverage: ${statusDashboardData.coverage}% assigned`
    });
  }
  
  // Understaffed days alert
  if (statusDashboardData.understaffedDays.length > 0) {
    const daysList = statusDashboardData.understaffedDays.slice(0, 3).join(", ");
    const more = statusDashboardData.understaffedDays.length > 3 ? ` +${statusDashboardData.understaffedDays.length - 3} more` : "";
    alerts.push({
      type: "warning",
      text: `${statusDashboardData.understaffedDays.length} day(s) not meeting minimum: ${daysList}${more}`
    });
  }
  
  // Pending requests alert
  if (statusDashboardData.swapRequests > 0) {
    alerts.push({
      type: "info",
      text: `${statusDashboardData.swapRequests} swap request(s) awaiting decision`
    });
  }
  
  if (statusDashboardData.timeoffRequests > 0) {
    alerts.push({
      type: "info",
      text: `${statusDashboardData.timeoffRequests} time-off request(s) pending`
    });
  }
  
  // Render alerts
  const alertsSection = document.getElementById("statusAlerts");
  const alertsList = document.getElementById("alertsList");
  
  if (alerts.length > 0) {
    alertsSection.style.display = "block";
    alertsList.innerHTML = alerts.map(alert => `
      <div style="
        padding:8px 10px;
        border-radius:6px;
        font-size:12px;
        background:${alert.type === 'warning' ? '#fff3cd' : '#d1ecf1'};
        color:${alert.type === 'warning' ? '#856404' : '#0c5460'};
        border-left:3px solid ${alert.type === 'warning' ? '#f39c12' : '#3498db'};
      ">
        ${escapeHtml(alert.text)}
      </div>
    `).join("");
  } else {
    alertsSection.style.display = "none";
  }
}

// Initialize when DOM is ready and supabase is available
document.addEventListener("DOMContentLoaded", () => {
  if (window.supabaseClient) {
    initStatusDashboard();
  }
});

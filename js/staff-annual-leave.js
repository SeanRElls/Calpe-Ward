/**
 * Staff Annual Leave View - Simple Version
 * Show calendar with leave and allow requesting a week
 * Request creates audit log and sends notification to admins
 */

const StaffAnnualLeaveModule = (() => {
  let currentUser = null;
  let userLeaveEntries = [];
  let rotaPeriods = [];
  let leaveBalance = null;
  let leaveAdjustments = [];

  /**
   * Initialize - show button for all staff
   */
  function init() {
    try {
      const annualLeaveBtn = document.getElementById('annualLeaveBtn');
      if (!annualLeaveBtn) {
        console.log('[Leave] Button not found');
        return;
      }

      // Wait for PermissionsModule and supabase client to be ready
      const checkReady = setInterval(() => {
        if (window.PermissionsModule?.getCurrentUser && window.supabaseClient) {
          clearInterval(checkReady);
          const user = window.PermissionsModule.getCurrentUser();
          if (user) {
            annualLeaveBtn.style.display = 'inline-flex';
            annualLeaveBtn.addEventListener('click', openAnnualLeaveView);
            console.log('[Leave] Initialized for user:', user.name);
          } else {
            console.log('[Leave] User not loaded yet');
          }
        }
      }, 100);

      // Timeout after 5 seconds
      setTimeout(() => clearInterval(checkReady), 5000);
    } catch (error) {
      console.error('[Leave] Init error:', error);
    }
  }

  /**
   * Open annual leave modal
   */
  async function openAnnualLeaveView() {
    try {
      currentUser = window.PermissionsModule?.getCurrentUser();
      if (!currentUser) {
        alert('Unable to load user information');
        return;
      }

      // Load all data
      await loadRotaPeriods();
      await loadLeaveBalance();

      showAnnualLeaveModal();
    } catch (error) {
      console.error('[Leave] Error:', error);
      alert('Error loading annual leave: ' + error.message);
    }
  }

  /**
   * Load rota periods and user leave entries via RPC
   */
  async function loadRotaPeriods() {
    // Get token from global window object
    const token = window.currentToken;
    if (!token) throw new Error('No active session token');

    // Call RPC function to get weeks with staff names
    const response = await window.supabaseClient.rpc('rpc_get_annual_leave_data', {
      p_token: token
    });

    if (response.error) throw response.error;

    const data = response.data || [];
    
    // Build periods array with separate nurse and NA names per week
    rotaPeriods = data.map(row => ({
      week_start: row.week_start,
      week_end: row.week_end,
      nurse_names: row.nurse_names || '',
      na_names: row.na_names || ''
    }));

    // Get user's leave entries via RPC
    const userLeaveResponse = await window.supabaseClient.rpc('staff_get_my_leave_entries', {
      p_token: token
    });

    if (userLeaveResponse.error) {
      console.error('[Leave] Error loading leave entries:', userLeaveResponse.error);
      userLeaveEntries = [];
    } else {
      userLeaveEntries = userLeaveResponse.data || [];
    }
  }

  /**
   * Load leave balance (for RN/SN only)
   */
  async function loadLeaveBalance() {
    const token = window.currentToken;
    if (!token) return;

    // Check if user is RN/SN (role_id 1 or 2)
    const isNA = currentUser.role_id === 3;
    if (isNA) {
      leaveBalance = null;
      leaveAdjustments = [];
      return;
    }

    try {
      // Get balance using staff RPC for current user
      const currentYear = new Date().getFullYear();
      const { data: balanceData, error: balanceError } = await window.supabaseClient.rpc("staff_get_my_leave_balance", {
        p_token: token,
        p_year: currentYear
      });

      if (balanceError) throw balanceError;
      leaveBalance = balanceData && balanceData.length > 0 ? balanceData[0] : null;

      // Get adjustments using staff RPC
      const { data: adjustmentsData, error: adjustmentsError } = await window.supabaseClient.rpc("staff_get_my_leave_adjustments", {
        p_token: token
      });

      if (adjustmentsError) throw adjustmentsError;
      leaveAdjustments = adjustmentsData || [];
    } catch (error) {
      console.error('[Leave] Error loading balance:', error);
      leaveBalance = null;
      leaveAdjustments = [];
    }
  }

  /**
   * Load user's leave entries - now handled by loadRotaPeriods
   */
  async function loadUserLeaveEntries() {
    // This is now handled by the RPC call in loadRotaPeriods
  }

  /**
   * Build entitlement section HTML
   */
  function buildEntitlementSection() {
    const isNA = currentUser.role_id === 3;
    const currentYear = new Date().getFullYear();

    let html = '';

    // Balance cards (RN/SN only)
    if (!isNA && leaveBalance) {
      const hasAdjustments = leaveBalance.adjustments_days && leaveBalance.adjustments_days !== 0;
      
      html += `
        <div style="margin-bottom: 20px;">
          <h3 style="margin: 0 0 12px 0; font-size: 14px; font-weight: 700; color: #1e293b;">
            📊 Entitlement (${leaveBalance.leave_year || currentYear})
          </h3>
          <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; margin-bottom: 14px;">
            <div style="padding: 10px; background: #f0fdf4; border: 1px solid #86efac; border-radius: 7px; text-align: center;">
              <div style="font-size: 10px; color: #166534; margin-bottom: 3px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.3px;">Base</div>
              <div style="font-size: 20px; font-weight: 700; color: #16a34a; line-height: 1;">${leaveBalance.annual_entitlement_days}</div>
            </div>
            
            <div style="padding: 10px; background: ${hasAdjustments ? '#fef3c7' : '#f9fafb'}; border: 1px solid ${hasAdjustments ? '#fcd34d' : '#e5e7eb'}; border-radius: 7px; text-align: center;">
              <div style="font-size: 10px; color: ${hasAdjustments ? '#92400e' : '#6b7280'}; margin-bottom: 3px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.3px;">Adjust</div>
              <div style="font-size: 20px; font-weight: 700; color: ${hasAdjustments ? '#f59e0b' : '#6b7280'}; line-height: 1;">
                ${leaveBalance.adjustments_days > 0 ? '+' : ''}${leaveBalance.adjustments_days}
              </div>
            </div>
            
            <div style="padding: 10px; background: #fef2f2; border: 1px solid #fca5a5; border-radius: 7px; text-align: center;">
              <div style="font-size: 10px; color: #991b1b; margin-bottom: 3px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.3px;">Taken</div>
              <div style="font-size: 20px; font-weight: 700; color: #dc2626; line-height: 1;">${leaveBalance.used_days}</div>
            </div>
            
            <div style="padding: 10px; background: #dbeafe; border: 1px solid #60a5fa; border-radius: 7px; text-align: center;">
              <div style="font-size: 10px; color: #1e40af; margin-bottom: 3px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.3px;">Remaining</div>
              <div style="font-size: 20px; font-weight: 700; color: #2563eb; line-height: 1;">${leaveBalance.remaining_days}</div>
            </div>
          </div>
      `;

      // Adjustments history
      if (leaveAdjustments && leaveAdjustments.length > 0) {
        html += `
          <div style="margin-bottom: 16px;">
            <div style="font-size: 12px; font-weight: 600; color: #64748b; margin-bottom: 8px;">📝 Adjustments</div>
            <div style="max-height: 150px; overflow-y: auto;">
        `;
        
        leaveAdjustments.forEach(adj => {
          const adjDate = new Date(adj.adjustment_date).toLocaleDateString('en-GB');
          const isPositive = adj.adjustment_days > 0;
          html += `
            <div style="background: white; border: 1px solid #e5e7eb; border-radius: 6px; padding: 8px; margin-bottom: 6px; font-size: 12px;">
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 3px;">
                <span style="font-weight: 600; color: ${isPositive ? '#16a34a' : '#dc2626'};">
                  ${isPositive ? '+' : ''}${adj.adjustment_days} days
                </span>
                <span style="font-size: 10px; color: #6b7280;">${adjDate}</span>
              </div>
              <div style="font-size: 11px; color: #6b7280;">${adj.reason || 'No reason'}</div>
            </div>
          `;
        });
        
        html += `
            </div>
          </div>
        `;
      }

      html += `</div>`;
    }

    // Leave taken section (for all staff including NAs)
    html += `
      <div>
        <h3 style="margin: 0 0 12px 0; font-size: 14px; font-weight: 700; color: #1e293b;">
          🗓️ Leave Taken (${currentYear})
        </h3>
    `;

    if (userLeaveEntries && userLeaveEntries.length > 0) {
      // Calculate total days using actual leave_days value
      let totalDays = 0;
      userLeaveEntries.forEach(entry => {
        totalDays += entry.leave_days || 0;
      });

      html += `
        <div style="padding: 10px; background: #ecfdf5; border: 1px solid #6ee7b7; border-radius: 7px; margin-bottom: 12px; text-align: center;">
          <div style="font-size: 10px; color: #065f46; margin-bottom: 3px; font-weight: 600;">Total Days</div>
          <div style="font-size: 22px; font-weight: 700; color: #059669;">${totalDays}</div>
        </div>
        
        <div style="max-height: 200px; overflow-y: auto;">
      `;

      userLeaveEntries.forEach(entry => {
        const startDate = new Date(entry.start_date);
        const endDate = new Date(entry.end_date);
        const dateRange = startDate.toLocaleDateString() === endDate.toLocaleDateString()
          ? startDate.toLocaleDateString('en-GB')
          : `${startDate.toLocaleDateString('en-GB')} - ${endDate.toLocaleDateString('en-GB')}`;

        html += `
          <div style="background: white; border: 1px solid #e5e7eb; border-radius: 6px; padding: 8px; margin-bottom: 6px;">
            <div style="font-weight: 600; color: #1f2937; font-size: 12px; margin-bottom: 2px;">${dateRange}</div>
            <div style="font-size: 11px; color: #6b7280;">${entry.leave_days} ${entry.leave_days === 1 ? 'day' : 'days'}</div>
          </div>
        `;
      });

      html += `</div>`;
    } else {
      html += `
        <p style="text-align: center; color: #9ca3af; padding: 20px 0; font-size: 12px;">No leave entries.</p>
      `;
    }

    html += `</div>`;

    return html;
  }

  /**
   * Show the annual leave modal with month view for entire 2026
   */
  function showAnnualLeaveModal() {
    const modalId = 'staffAnnualLeaveModal';
    let modal = document.getElementById(modalId);

    if (!modal) {
      modal = document.createElement('div');
      modal.id = modalId;
      modal.className = 'modal';
      modal.style.cssText = `
        display: none;
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background: rgba(0, 0, 0, 0.5);
        justify-content: center;
        align-items: center;
        z-index: 10000;
      `;
      document.body.appendChild(modal);
    }

    // Start with current month, but constrained to 2026
    let currentDate = new Date();
    if (currentDate.getFullYear() > 2026) {
      currentDate = new Date(2026, 11, 31); // Dec 2026
    } else if (currentDate.getFullYear() < 2026) {
      currentDate = new Date(2026, 0, 1); // Jan 2026
    }
    
    const createMonthView = () => {
      const year = currentDate.getFullYear();
      const month = currentDate.getMonth();
      const monthName = currentDate.toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
      
      const today = new Date();
      today.setHours(0, 0, 0, 0);

      // Build entitlement section HTML
      const entitlementHTML = buildEntitlementSection();

      // Filter weeks that fall within this month
      const monthWeeks = rotaPeriods.filter(week => {
        const weekStart = new Date(week.week_start);
        return weekStart.getMonth() === month && weekStart.getFullYear() === year;
      });

      // Build weeks HTML
      const weeksHTML = monthWeeks.map(week => {
        const weekStart = new Date(week.week_start);
        const weekEnd = new Date(week.week_end);
        const isFuture = weekStart > today;
        const isUserOnLeave = userLeaveEntries.some(entry => {
          const entryStart = new Date(entry.start_date);
          const entryEnd = new Date(entry.end_date);
          return entryStart <= weekEnd && entryEnd >= weekStart;
        });

        // Handle NULL staff_names from RPC (appears as null in JS)
        let nurseNames = (week.nurse_names && week.nurse_names !== 'null') ? week.nurse_names : '';
        let naNames = (week.na_names && week.na_names !== 'null') ? week.na_names : '';
        let staffNames = [nurseNames, naNames].filter(n => n).join(', ');
        let actionHTML = '';

        if (isFuture && !isUserOnLeave) {
          actionHTML = `<button class="btn-request" data-week-start="${week.week_start}" data-week-end="${week.week_end}" style="padding:4px 8px; font-size:11px; background:#3b82f6; color:white; border:none; border-radius:4px; cursor:pointer; white-space:nowrap;">📝 Request</button>`;
        } else if (isUserOnLeave) {
          actionHTML = `<span style="font-size:11px; color:#10b981;">✅ Requested</span>`;
        }

        return `
          <tr>
            <td style="padding:8px; border-bottom:1px solid #e5e7eb; font-size:13px;">${formatDate(weekStart)} - ${formatDate(weekEnd)}</td>
            <td style="padding:8px; border-bottom:1px solid #e5e7eb; font-size:13px; color:#333;">${staffNames || '—'}</td>
            <td style="padding:8px; border-bottom:1px solid #e5e7eb; text-align:right;">${actionHTML}</td>
          </tr>
        `;
      }).join('');

      const canGoPrev = month > 0 || year > 2026;
      const canGoNext = month < 11 || year < 2026;

      const content = `
        <style>
          .leave-modal-content {
            max-width: 900px;
            width: 95%;
            background: white;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            overflow: hidden;
            display: flex;
            flex-direction: column;
            max-height: 90vh;
          }
          
          .leave-modal-body {
            display: flex;
            flex: 1;
            overflow: hidden;
            flex-direction: row;
          }
          
          .leave-modal-sidebar {
            width: 340px;
            min-width: 280px;
            padding: 16px;
            border-right: 1px solid #e5e7eb;
            overflow-y: auto;
            background: #fafafa;
            flex-shrink: 0;
          }
          
          .leave-modal-calendar {
            flex: 1;
            display: flex;
            flex-direction: column;
            overflow: hidden;
          }
          
          @media (max-width: 768px) {
            .leave-modal-content {
              width: 100%;
              max-width: 100%;
              max-height: 100vh;
              height: 100vh;
              border-radius: 0;
            }
            
            .leave-modal-body {
              flex-direction: column;
            }
            
            .leave-modal-sidebar {
              width: 100%;
              min-width: 100%;
              max-height: 25vh;
              padding: 6px;
              border-right: none;
              border-bottom: 1px solid #e5e7eb;
              font-size: 10px;
            }
            
            .leave-modal-sidebar h3 {
              font-size: 11px !important;
              margin: 4px 0 2px 0 !important;
            }
            
            .leave-modal-sidebar p {
              font-size: 10px !important;
              margin: 2px 0 !important;
              line-height: 1.2 !important;
            }
            
            .leave-modal-content > div:first-of-type {
              padding: 6px 8px !important;
            }
            
            .leave-modal-content h2 {
              font-size: 13px !important;
            }
            
            .leave-modal-content button[onclick*="display"] {
              font-size: 20px !important;
              padding: 4px 8px !important;
              min-width: 36px !important;
              min-height: 36px !important;
            }
            
            .leave-modal-calendar > div:first-child {
              padding: 4px 6px !important;
              gap: 2px !important;
            }
            
            .leave-modal-calendar h3 {
              font-size: 12px !important;
              min-width: 80px !important;
            }
            
            .leave-modal-calendar button {
              font-size: 14px !important;
              padding: 4px 6px !important;
              min-width: 32px !important;
              min-height: 32px !important;
            }
            
            #viewFullYear {
              font-size: 9px !important;
              padding: 4px 6px !important;
              min-height: 32px !important;
            }
            
            .leave-modal-calendar table th {
              font-size: 9px !important;
              padding: 4px 2px !important;
            }
            
            .leave-modal-calendar table td {
              font-size: 9px !important;
              padding: 4px 2px !important;
            }
            
            .leave-modal-calendar table th:first-child,
            .leave-modal-calendar table td:first-child {
              display: none;
            }
            
            .btn-request {
              font-size: 8px !important;
              padding: 2px 4px !important;
            }
          }
        </style>
        <div class="leave-modal-content">
          <!-- Header -->
          <div style="display: flex; justify-content: space-between; align-items: center; padding: 16px; background: #f3f4f6; border-bottom: 1px solid #e5e7eb;">
            <h2 style="margin: 0; font-size: 16px; font-weight: 700;">🏖️ Annual Leave</h2>
            <button onclick="document.getElementById('${modalId}').style.display='none';" style="font-size: 24px; border: none; background: none; cursor: pointer; padding: 4px 12px; min-width: 44px; min-height: 44px; display: flex; align-items: center; justify-content: center;">&times;</button>
          </div>

          <!-- Content Area -->
          <div class="leave-modal-body">
            <!-- Left: Entitlement -->
            <div class="leave-modal-sidebar">
              ${entitlementHTML}
            </div>

            <!-- Right: Calendar -->
            <div class="leave-modal-calendar">
              <!-- Month Navigation -->
              <div style="display: flex; justify-content: space-between; align-items: center; padding: 12px 16px; background: white; border-bottom: 1px solid #e5e7eb; flex-wrap: wrap; gap: 8px;">
                <button id="prevMonth" style="background: none; border: none; font-size: 20px; cursor: pointer; padding: 8px 12px; min-width: 44px; min-height: 44px; opacity: ${canGoPrev ? '1' : '0.3'}; ${canGoPrev ? '' : 'cursor: not-allowed;'}">&lt;</button>
                <h3 style="margin: 0; font-size: 15px; font-weight: 600; flex: 1; text-align: center; min-width: 120px;">${monthName}</h3>
                <button id="nextMonth" style="background: none; border: none; font-size: 20px; cursor: pointer; padding: 8px 12px; min-width: 44px; min-height: 44px; opacity: ${canGoNext ? '1' : '0.3'}; ${canGoNext ? '' : 'cursor: not-allowed;'}">&gt;</button>
                <button id="viewFullYear" style="background: #10b981; color: white; border: none; border-radius: 4px; padding: 8px 16px; font-size: 12px; cursor: pointer; white-space: nowrap; min-height: 44px;">📅 View Year</button>
              </div>

              <!-- Table -->
              <div style="flex: 1; overflow-y: auto;">
                <table style="width: 100%; border-collapse: collapse;">
                  <thead>
                    <tr style="background: #f0f4f8; border-bottom: 2px solid #d1d5db; position: sticky; top: 0;">
                      <th style="padding: 12px; text-align: left; font-size: 12px; font-weight: 600;">Week</th>
                      <th style="padding: 12px; text-align: left; font-size: 12px; font-weight: 600;">Staff on Leave</th>
                      <th style="padding: 12px; text-align: right; font-size: 12px; font-weight: 600;">Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    ${weeksHTML || '<tr><td colspan="3" style="padding: 20px; text-align: center; color: #999;">No weeks in this month</td></tr>'}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      `;

      modal.innerHTML = content;

      // Attach View Full Year button
      document.getElementById('viewFullYear').addEventListener('click', () => {
        openFullYearView();
      });

      // Attach month navigation
      document.getElementById('prevMonth').addEventListener('click', () => {
        if (canGoPrev) {
          if (month === 0) {
            currentDate.setFullYear(currentDate.getFullYear() - 1);
            currentDate.setMonth(11);
          } else {
            currentDate.setMonth(currentDate.getMonth() - 1);
          }
          createMonthView();
        }
      });

      document.getElementById('nextMonth').addEventListener('click', () => {
        if (canGoNext) {
          if (month === 11) {
            currentDate.setFullYear(currentDate.getFullYear() + 1);
            currentDate.setMonth(0);
          } else {
            currentDate.setMonth(currentDate.getMonth() + 1);
          }
          createMonthView();
        }
      });

      // Attach request button listeners
      modal.querySelectorAll('.btn-request').forEach(btn => {
        btn.addEventListener('click', (e) => {
          const weekStart = e.target.dataset.weekStart;
          const weekEnd = e.target.dataset.weekEnd;
          requestLeave(weekStart, weekEnd);
        });
      });
    };

    createMonthView();
    modal.style.display = 'flex';
    console.log('[Leave] Month view modal displayed for 2026');
  }

  /**
   * Request leave for a week
   */
  async function requestLeave(weekStart, weekEnd) {
    if (!confirm(`Request leave for the week of ${formatDate(new Date(weekStart))}?`)) {
      return;
    }

    try {
      console.log('[Leave] Submitting request with:', {
        token: window.currentToken,
        week_start: weekStart,
        week_end: weekEnd,
        staff_name: currentUser.name
      });

      // Submit leave request via RPC
      const { data, error } = await window.supabaseClient.rpc('rpc_submit_leave_request', {
        p_token: window.currentToken,
        p_week_start: weekStart,
        p_week_end: weekEnd,
        p_staff_name: currentUser.name
      });

      if (error) throw error;

      alert('✅ Leave request submitted! Admins will review and add you to the rota.');
      document.getElementById('staffAnnualLeaveModal').style.display = 'none';
    } catch (error) {
      console.error('[Leave] Error:', error);
      alert('Error: ' + error.message);
    }
  }

  /**
   * Get all weeks from periods
   */
  function getAllWeeks() {
    const weeks = [];
    rotaPeriods.forEach(period => {
      const start = new Date(period.start_date);
      const end = new Date(period.end_date);

      for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 7)) {
        const weekStart = new Date(d);
        const weekEnd = new Date(d);
        weekEnd.setDate(weekEnd.getDate() + 6);

        weeks.push({
          week_start: weekStart.toISOString().split('T')[0],
          week_end: weekEnd.toISOString().split('T')[0]
        });
      }
    });
    return weeks;
  }

  /**
   * Check if user is on leave for a week
   */
  function isUserOnLeave(weekStart, weekEnd) {
    const start = new Date(weekStart);
    const end = new Date(weekEnd);

    return userLeaveEntries.some(entry => {
      const entryStart = new Date(entry.start_date);
      const entryEnd = new Date(entry.end_date);
      return entryStart <= end && entryEnd >= start;
    });
  }

  /**
   * Format date as "Jan 27"
   */
  function formatDate(date) {
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  }

  /**
   * Open full year view in new window - matches admin annual view exactly
   */
  function openFullYearView() {
    const printWindow = window.open('', '_blank', 'width=1200,height=800');
    
    const currentYear = new Date().getFullYear();
    const yearEnd = new Date(currentYear, 11, 31);

    // Group rotaPeriods weeks by month
    function getMonthWeeks(monthIndex) {
      return rotaPeriods.filter(period => {
        const weekStart = new Date(period.week_start);
        return weekStart.getMonth() === monthIndex && weekStart.getFullYear() === currentYear;
      });
    }

    // Helper to get staff for a week by role
    function getStaffForWeek(week, roleType) {
      if (!week) return '';
      
      const namesField = roleType === 'nurse' ? week.nurse_names : week.na_names;
      const names = (namesField && namesField !== 'null') ? namesField.split(', ').filter(n => n.trim()) : [];
      if (names.length === 0) return '';
      
      return names.map(name => {
        return `<div style="font-weight:700; color:#0f172a; background:#e0f2fe; border:1px solid #bae6fd; border-radius:4px; padding:3px 6px; margin:2px 0;">${name}</div>`;
      }).join('');
    }

    // Build month tables HTML
    let tablesHTML = '';
    const fixedColumns = 5;

    for (let monthIndex = 0; monthIndex < 12; monthIndex++) {
      const monthWeeks = getMonthWeeks(monthIndex);
      if (!monthWeeks.length) continue;

      const monthName = new Date(currentYear, monthIndex, 1).toLocaleDateString('en-GB', { month: 'long', year: 'numeric' });

      const paddedWeeks = [...monthWeeks];
      while (paddedWeeks.length < fixedColumns) paddedWeeks.push(null);

      let headerCells = `<th style="padding:8px 12px; text-align:left; font-weight:700; width:140px; border:1px solid #2c5aa0; font-size:12px;">${monthName}</th>`;
      paddedWeeks.forEach(week => {
        if (!week) {
          headerCells += `<th style="padding:8px 6px; text-align:center; border:1px solid #2c5aa0; background:#2c5aa0; color:white; font-weight:600; min-width:110px; font-size:11px;">&nbsp;</th>`;
        } else {
          const weekStart = new Date(week.week_start);
          const dayNum = weekStart.getDate();
          const monthNum = weekStart.getMonth() + 1;
          const yearNum = weekStart.getFullYear().toString().slice(-2);
          headerCells += `<th style="padding:8px 6px; text-align:center; border:1px solid #2c5aa0; background:#2c5aa0; color:white; font-weight:700; min-width:110px; font-size:11px;">${dayNum}.${String(monthNum).padStart(2, '0')}.${yearNum}</th>`;
        }
      });

      let nurseRowCells = `<td style="padding:10px 12px; font-weight:700; border:1px solid #e5e7eb; background:#a8d5f7; color:#0f172a;">Nurse</td>`;
      paddedWeeks.forEach(week => {
        const cellContent = getStaffForWeek(week, 'nurse');
        nurseRowCells += `<td style="padding:10px 6px; border:1px solid #e5e7eb; text-align:left; font-size:12px; min-width:110px; vertical-align:top;">${cellContent}</td>`;
      });

      let naRowCells = `<td style="padding:10px 12px; font-weight:700; border:1px solid #e5e7eb; background:#a8d5f7; color:#0f172a;">Nursing Assistant</td>`;
      paddedWeeks.forEach(week => {
        const cellContent = getStaffForWeek(week, 'na');
        naRowCells += `<td style="padding:10px 6px; border:1px solid #e5e7eb; text-align:left; font-size:12px; min-width:110px; vertical-align:top;">${cellContent}</td>`;
      });

      tablesHTML += `
        <table style="width:100%; border-collapse:collapse; font-size:12px; margin-bottom:10px; table-layout:fixed;">
          <thead>
            <tr style="background:#2c5aa0; color:white;">
              ${headerCells}
            </tr>
          </thead>
          <tbody>
            <tr style="background:#a8d5f7;">
              ${nurseRowCells}
            </tr>
            <tr style="background:#a8d5f7;">
              ${naRowCells}
            </tr>
          </tbody>
        </table>
      `;
    }

    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <title>Annual Leave ${currentYear}</title>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            margin: 20px;
            background: white;
          }
          @media print {
            body { margin: 0; }
            .no-print { display: none; }
          }
        </style>
      </head>
      <body>
        <div style="text-align: center; margin-bottom: 20px;" class="no-print">
          <button onclick="window.print()" style="background: #3b82f6; color: white; border: none; padding: 10px 20px; border-radius: 6px; cursor: pointer; font-size: 14px; margin-right: 10px;">🖨️ Print</button>
          <button onclick="window.close()" style="background: #64748b; color: white; border: none; padding: 10px 20px; border-radius: 6px; cursor: pointer; font-size: 14px;">✖️ Close</button>
        </div>
        ${tablesHTML}
      </body>
      </html>
    `;

    printWindow.document.write(html);
    printWindow.document.close();
  }

  return {
    init
  };
})();

// Initialize when DOM ready or after a delay
setTimeout(() => {
  StaffAnnualLeaveModule.init();
}, 500);

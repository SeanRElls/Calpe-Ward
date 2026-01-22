// admin-periods.js
// Period management, week toggles, and period generation for admin panel

console.log("[ADMIN-PERIODS.JS] Script loaded");

// DOM Elements
const periodsPageTabs = Array.from(document.querySelectorAll('.subtab[data-periods-page]'));
const periodsPages = [
  document.getElementById('periodsPageManage'),
  document.getElementById('periodsPageGenerate')
].filter(Boolean);

const adminPeriodSelect = document.getElementById('adminPeriodSelect');
const adminPeriodMeta = document.getElementById('adminPeriodMeta');
const adminSetActiveBtn = document.getElementById('adminSetActiveBtn');
const adminToggleHiddenBtn = document.getElementById('adminToggleHiddenBtn');
const adminClosesAtInput = document.getElementById('adminClosesAtInput');
const adminClosesAtSaveBtn = document.getElementById('adminClosesAtSaveBtn');
const adminClosesAtClearBtn = document.getElementById('adminClosesAtClearBtn');
const adminClosesAtHelp = document.getElementById('adminClosesAtHelp');
const adminWeeksList = document.getElementById('adminWeeksList');
const adminGeneratePreview = document.getElementById('adminGeneratePreview');
const adminGenerateFutureList = document.getElementById('adminGenerateFutureList');
const adminGenerateBtn = document.getElementById('adminGenerateBtn');

let adminSelectedPeriodId = null;
let periodsCache = [];

// Helper functions
function fmt(date) {
  const d = new Date(date);
  const day = d.getDate();
  const mon = d.toLocaleString('en-GB', { month: 'short' });
  return `${day} ${mon}`;
}

function isoDate(date) {
  const d = new Date(date);
  return d.toISOString().split('T')[0];
}

function addDays(date, days) {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}

function startOfWeekSunday(date) {
  const d = new Date(date);
  const day = d.getDay();
  const diff = day === 0 ? 0 : -day;
  d.setDate(d.getDate() + diff);
  d.setHours(0, 0, 0, 0);
  return d;
}

function datetimeLocalToISOString(dtLocalValue) {
  if (!dtLocalValue) return null;
  return new Date(dtLocalValue).toISOString();
}

function isPeriodClosed(period) {
  if (!period?.closes_at) return false;
  const now = new Date();
  const deadline = new Date(period.closes_at);
  return now > deadline;
}

// Subtab switching for periods pages
periodsPageTabs.forEach(tab => {
  tab.addEventListener('click', () => {
    const page = tab.dataset.periodsPage;
    
    periodsPageTabs.forEach(t => t.classList.remove('is-active'));
    tab.classList.add('is-active');
    
    periodsPages.forEach(p => p.style.display = 'none');
    
    if (page === 'manage') {
      document.getElementById('periodsPageManage')?.style.setProperty('display', 'block');
    } else if (page === 'generate') {
      document.getElementById('periodsPageGenerate')?.style.setProperty('display', 'block');
      refreshGeneratePreview();
    }
  });
});

// Fetch all periods
async function fetchRotaPeriods() {
  const { data, error } = await supabaseClient.rpc("rpc_get_rota_periods", {
    p_token: window.currentToken
  });
  
  if (error) throw error;
  const periods = data || [];
  periods.sort((a, b) => new Date(b.start_date) - new Date(a.start_date));
  return periods;
}

// Load periods into dropdown
async function loadAdminPeriodsForDropdown() {
  if (!adminPeriodSelect) return;

  adminPeriodMeta.textContent = 'Loading…';
  adminWeeksList.textContent = 'Loading…';

  let periods;
  try {
    periods = await fetchRotaPeriods();
  } catch (e) {
    console.error(e);
    adminPeriodMeta.textContent = 'Failed to load periods.';
    adminWeeksList.textContent = 'Failed to load weeks.';
    return;
  }

  periodsCache = periods;

  // Fill dropdown
  adminPeriodSelect.innerHTML = '';
  for (const p of periods) {
    const opt = document.createElement('option');
    opt.value = p.id;
    const s = fmt(new Date(p.start_date));
    const e = fmt(new Date(p.end_date));
    opt.textContent = `${s} – ${e}${p.is_active ? ' ★' : ''}${p.is_hidden ? ' (hidden)' : ''}`;
    adminPeriodSelect.appendChild(opt);
  }

  // Default selection
  if (!adminSelectedPeriodId) {
    const active = periods.find(p => p.is_active) || periods[periods.length - 1];
    adminSelectedPeriodId = active?.id || periods[0]?.id;
  }

  adminPeriodSelect.value = String(adminSelectedPeriodId);

  renderAdminPeriodMeta(adminSelectedPeriodId);
  await loadAdminWeeks(adminSelectedPeriodId);
  renderAdminCloseTime(adminSelectedPeriodId);
}

function renderAdminPeriodMeta(periodId) {
  const p = periodsCache.find(x => String(x.id) === String(periodId));
  if (!p) {
    adminPeriodMeta.textContent = '';
    return;
  }

  const bits = [];
  if (p.is_active) bits.push('✅ Active');
  if (p.is_hidden) bits.push('🙈 Hidden');
  adminPeriodMeta.textContent = bits.join(' · ') || '—';
}

function renderAdminCloseTime(periodId) {
  const p = periodsCache.find(x => String(x.id) === String(periodId));
  if (!p) return;

  if (p.closes_at) {
    const dt = new Date(p.closes_at);
    const localStr = dt.toISOString().slice(0, 16);
    adminClosesAtInput.value = localStr;
  } else {
    adminClosesAtInput.value = '';
  }
}

async function loadAdminWeeks(periodId) {
  adminWeeksList.textContent = 'Loading weeks…';

  const { data, error } = await supabaseClient.rpc("rpc_get_rota_weeks", {
    p_token: window.currentToken,
    p_period_id: periodId
  });

  if (error) {
    console.error(error);
    adminWeeksList.textContent = 'Failed to load weeks.';
    return;
  }

  const weeks = (data || [])
    .map(w => ({
      weekId: w.id,
      open: !!w.open,
      openAfterClose: !!w.open_after_close,
      weekStart: new Date(w.week_start),
      weekEnd: new Date(w.week_end)
    }))
    .sort((a, b) => a.weekStart - b.weekStart);

  if (!weeks.length) {
    adminWeeksList.textContent = 'No weeks found for this period.';
    return;
  }

  const p = periodsCache.find(x => String(x.id) === String(periodId));
  const periodClosed = isPeriodClosed(p);

  adminWeeksList.innerHTML = weeks.map(w => {
    const s = fmt(w.weekStart);
    const e = fmt(w.weekEnd);
    const isOpen = periodClosed ? !!w.openAfterClose : !!w.open;

    const pill = isOpen
      ? `<span style="display:inline-block; padding:2px 8px; border-radius:999px; font-size:11px; font-weight:800; background:#e9fff0; border:1px solid #9fe0b1; color:#0b6b2b;">OPEN</span>`
      : `<span style="display:inline-block; padding:2px 8px; border-radius:999px; font-size:11px; font-weight:800; background:#ffecec; border:1px solid #ffb3b3; color:#8a1f1f;">CLOSED</span>`;

    const lockNote = `
      <div style="margin-top:4px; font-size:11px; color:#666;">
        ${isOpen ? 'Requests open for staff' : 'Requests locked for staff'} 
        ${periodClosed ? '(after close time)' : '(before close time)'}
      </div>
    `;

    const btnText = isOpen ? 'Close week' : 'Open week';

    return `
      <div style="display:flex; justify-content:space-between; align-items:center; gap:10px; padding:10px 0; border-bottom:1px solid #eee;">
        <div>
          <div style="font-weight:700;">${s} – ${e}</div>
          <div style="margin-top:4px;">${pill}</div>
          ${lockNote}
        </div>
        <button type="button"
          class="btn week-toggle-btn"
          data-week-id="${w.weekId}"
          data-open="${w.open ? '1' : '0'}"
          data-open-after-close="${w.openAfterClose ? '1' : '0'}"
          data-period-closed="${periodClosed ? '1' : '0'}"
        >
          ${btnText}
        </button>
      </div>
    `;
  }).join('');

  // Bind toggle buttons
  adminWeeksList.querySelectorAll('button[data-week-id]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const weekId = btn.dataset.weekId;
      const open = btn.dataset.open === '1';
      const openAfterClose = btn.dataset.openAfterClose === '1';
      const periodClosed = btn.dataset.periodClosed === '1';

      let nextOpen = open;
      let nextOpenAfterClose = openAfterClose;

      if (periodClosed) {
        nextOpenAfterClose = !openAfterClose;
      } else {
        nextOpen = !open;
      }

      try {
        const adminId = window.currentUser?.id;
        if (!adminId) {
          alert('No current admin user found. Please re-login.');
          return;
        }

        btn.disabled = true;
        const { error } = await supabaseClient.rpc('admin_set_week_open_flags', {
          p_token: window.currentToken,
          p_week_id: weekId,
          p_open: nextOpen,
          p_open_after_close: nextOpenAfterClose
        });
        if (error) throw error;

        await loadAdminWeeks(periodId);
      } catch (e) {
        console.error(e);
        alert('Failed to toggle week. Check console.');
      } finally {
        btn.disabled = false;
      }
    });
  });
}

// Period actions
if (adminPeriodSelect) {
  adminPeriodSelect.addEventListener('change', async () => {
    adminSelectedPeriodId = adminPeriodSelect.value;
    renderAdminPeriodMeta(adminSelectedPeriodId);
    await loadAdminWeeks(adminSelectedPeriodId);
    renderAdminCloseTime(adminSelectedPeriodId);
  });
}

if (adminSetActiveBtn) {
  adminSetActiveBtn.addEventListener('click', async () => {
    if (!adminSelectedPeriodId) return alert('Select a period first.');

    try {
      adminSetActiveBtn.disabled = true;
      const { error } = await supabaseClient.rpc('admin_set_active_period', {
        p_token: window.currentToken,
        p_period_id: adminSelectedPeriodId
      });
      if (error) throw error;

      await loadAdminPeriodsForDropdown();
      alert('Period set as active.');
    } catch (e) {
      console.error(e);
      alert('Failed to set active period. Check console.');
    } finally {
      adminSetActiveBtn.disabled = false;
    }
  });
}

if (adminToggleHiddenBtn) {
  adminToggleHiddenBtn.addEventListener('click', async () => {
    if (!adminSelectedPeriodId) return alert('Select a period first.');

    try {
      adminToggleHiddenBtn.disabled = true;
      const { error } = await supabaseClient.rpc('admin_toggle_hidden_period', {
        p_token: window.currentToken,
        p_period_id: adminSelectedPeriodId
      });
      if (error) throw error;

      await loadAdminPeriodsForDropdown();
      alert('Period visibility toggled.');
    } catch (e) {
      console.error(e);
      alert('Failed to toggle hidden. Check console.');
    } finally {
      adminToggleHiddenBtn.disabled = false;
    }
  });
}

if (adminClosesAtSaveBtn) {
  adminClosesAtSaveBtn.addEventListener('click', async () => {
    if (!adminSelectedPeriodId) return alert('Select a period first.');
    if (!adminClosesAtInput?.value) return alert('Pick a date/time first.');

    try {
      adminClosesAtSaveBtn.disabled = true;
      const iso = datetimeLocalToISOString(adminClosesAtInput.value);

      const { error } = await supabaseClient.rpc('admin_set_period_closes_at', {
        p_token: window.currentToken,
        p_period_id: adminSelectedPeriodId,
        p_closes_at: iso
      });
      if (error) throw error;

      // Reset all weeks to closed after close time
      await resetWeeksAfterClose(adminSelectedPeriodId);
      await loadAdminPeriodsForDropdown();
      alert('Close time saved. All weeks set to closed after deadline.');
    } catch (e) {
      console.error(e);
      alert('Failed to save close time. Check console.');
    } finally {
      adminClosesAtSaveBtn.disabled = false;
    }
  });
}

if (adminClosesAtClearBtn) {
  adminClosesAtClearBtn.addEventListener('click', async () => {
    if (!adminSelectedPeriodId) return alert('Select a period first.');

    try {
      adminClosesAtClearBtn.disabled = true;
      const { error } = await supabaseClient.rpc('admin_set_period_closes_at', {
        p_token: window.currentToken,
        p_period_id: adminSelectedPeriodId,
        p_closes_at: null
      });
      if (error) throw error;

      adminClosesAtInput.value = '';
      await loadAdminPeriodsForDropdown();
      alert('Close time cleared.');
    } catch (e) {
      console.error(e);
      alert('Failed to clear close time. Check console.');
    } finally {
      adminClosesAtClearBtn.disabled = false;
    }
  });
}

async function resetWeeksAfterClose(periodId) {
  const { error: resetErr } = await supabaseClient.rpc("admin_set_weeks_open_after_close", {
    p_token: window.currentToken,
    p_period_id: periodId,
    p_open_after_close: false
  });

  if (resetErr) throw resetErr;
}

// Generate new period
function computeNextPeriodRange() {
  if (!periodsCache?.length) return null;

  const latest = [...periodsCache]
    .sort((a, b) => new Date(a.end_date) - new Date(b.end_date))
    .at(-1);

  if (!latest?.end_date) return null;

  const lastEnd = new Date(latest.end_date);

  let start = addDays(lastEnd, 1);
  while (start.getDay() !== 0) start = addDays(start, 1);

  const end = addDays(start, 34);
  return { start, end, latest };
}

function computeFuturePeriodRanges(count = 12) {
  const first = computeNextPeriodRange();
  if (!first) return [];

  const results = [];
  let currentStart = new Date(first.start);

  for (let i = 0; i < count; i++) {
    const start = new Date(currentStart);
    const end = addDays(start, 34);
    results.push({ start, end, index: i });

    // Next period starts the day after this one ends (5 weeks = 35 days)
    currentStart = addDays(start, 35);
  }

  return results;
}

function refreshGeneratePreview() {
  const r = computeNextPeriodRange();
  if (!r) {
    adminGeneratePreview.textContent = 'Cannot preview. No periods loaded.';
    if (adminGenerateFutureList) adminGenerateFutureList.textContent = 'Cannot preview. No periods loaded.';
    return;
  }

  adminGeneratePreview.textContent =
    `Next period: ${fmt(r.start)} – ${fmt(r.end)} (5 weeks, Sun–Sat).`;

  if (adminGenerateFutureList) {
    const future = computeFuturePeriodRanges(12);
    adminGenerateFutureList.innerHTML = future
      .map(p => {
        const label = p.index === 0 ? 'Next' : `+${p.index}`;
        return `<div style="padding:6px 0; border-bottom:1px solid #eee; display:flex; justify-content:space-between; gap:8px;">
          <span style="font-weight:600; color:#111;">${label}</span>
          <span style="flex:1; text-align:right; color:#333;">${fmt(p.start)} – ${fmt(p.end)}</span>
        </div>`;
      })
      .join('');
  }
}

if (adminGenerateBtn) {
  adminGenerateBtn.addEventListener('click', async () => {
    try {
      const r = computeNextPeriodRange();
      if (!r) {
        alert('Cannot generate: no periods loaded.');
        return;
      }

      const ok = confirm(`Generate new 5-week period:\n${fmt(r.start)} – ${fmt(r.end)} ?`);
      if (!ok) return;

      adminGenerateBtn.disabled = true;
      adminGeneratePreview.textContent = 'Generating…';

      const startStr = isoDate(r.start);
      const endStr = isoDate(r.end);
      const periodName = `${fmt(r.start)} – ${fmt(r.end)}`;

      const { data: periodId, error } = await supabaseClient.rpc(
        'admin_create_five_week_period',
        {
          p_token: window.currentToken,
          p_name: periodName,
          p_start_date: startStr,
          p_end_date: endStr
        }
      );

      if (error) throw error;

      await loadAdminPeriodsForDropdown();
      refreshGeneratePreview();

      adminSelectedPeriodId = periodId;
      adminPeriodSelect.value = String(periodId);
      renderAdminPeriodMeta(periodId);
      await loadAdminWeeks(periodId);
      renderAdminCloseTime(periodId);

      alert('Generated new 5-week period.');
    } catch (e) {
      console.error(e);
      const msg = e?.message || e?.details || e?.hint || JSON.stringify(e, null, 2);
      alert('Generate failed:\n\n' + msg);
    } finally {
      adminGenerateBtn.disabled = false;
      refreshGeneratePreview();
    }
  });
}

// Initialize when rota-periods panel becomes active
const rotaPeriodsObserver = new MutationObserver(() => {
  const rotaPeriods = document.getElementById('rota-periods');
  if (rotaPeriods && rotaPeriods.style.display !== 'none' && !periodsCache.length) {
    loadAdminPeriodsForDropdown();
    refreshGeneratePreview();
  }
});

const rotaPeriodsPanel = document.getElementById('rota-periods');
if (rotaPeriodsPanel) {
  rotaPeriodsObserver.observe(rotaPeriodsPanel, {
    attributes: true,
    attributeFilter: ['style']
  });
}

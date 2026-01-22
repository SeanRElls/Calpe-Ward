// periods-shared.js
// Shared period loading functionality for rota.html and preview.html

console.log("[PERIODS-SHARED.JS] Script loaded");

/**
 * Load available rota periods and populate the periodSelect dropdown
 * Requires periodMap (Map) and normalizeText (function) to be in global scope
 */
async function loadPeriods() {
  try {
    const token = window.currentToken || sessionStorage.getItem('calpe_ward_token');
    if (!token) {
      throw new Error('Session token not available.');
    }
    const { data, error } = await window.supabaseClient.rpc('rpc_get_rota_periods', {
      p_token: token
    });
    
    if (error) throw error;
    const rows = (data || [])
      .sort((a, b) => new Date(b.start_date) - new Date(a.start_date))
      .slice(0, 12);
    
    const select = document.getElementById('periodSelect');
    if (!select) {
      console.warn("[PERIODS-SHARED.JS] periodSelect element not found");
      return;
    }
    
    // Clear existing options (including placeholder)
    select.innerHTML = '';
    
    rows.forEach(period => {
      const option = document.createElement('option');
      option.value = period.id;
      // Format dates nicely
      const startDate = new Date(period.start_date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
      const endDate = new Date(period.end_date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
      
      // Use normalizeText if available, otherwise use period.name directly
      const safeName = typeof normalizeText === 'function' ? normalizeText(period.name) : period.name;
      option.textContent = `${safeName} (${startDate} - ${endDate})`;
      select.appendChild(option);
      
      // Update periodMap if it exists in global scope
      if (typeof periodMap !== 'undefined' && periodMap instanceof Map) {
        periodMap.set(period.id, {
          id: period.id,
          name: period.name,
          start_date: period.start_date,
          end_date: period.end_date
        });
      }
    });
  } catch (e) {
    console.error('[PERIODS-SHARED.JS] Error loading periods:', e);
    if (typeof showStatus === 'function') {
      showStatus('Error loading periods: ' + e.message, 'error');
    }
  }
}

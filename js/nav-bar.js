/**
 * Centralized Navigation Bar Component
 * Includes: Page navigation, logo, user info, view-as functionality, logout
 * Works with both rota.html and requests.html structures
 */

function initializeNavBar() {
  // Get current page
  const currentPage = window.location.pathname.split('/').pop() || 'rota.html';
  
  // Set active nav link styling
  const requestsLink = document.querySelector('a[href="requests.html"]');
  const rotaLink = document.querySelector('a[href="rota.html"]');
  
  if (requestsLink && (currentPage === 'requests.html' || currentPage.includes('requests'))) {
    requestsLink.style.fontWeight = '600';
  }
  if (rotaLink && (currentPage === 'rota.html' || !currentPage.includes('requests'))) {
    rotaLink.style.fontWeight = '600';
  }
  
  // Update admin nav link visibility based on permissions or user status
  const navAdminLink = document.getElementById('navAdminLink');
  if (navAdminLink) {
    // Check permissions from PermissionsModule or look for admin badge
    const isAdmin = window.PermissionsModule?.getCurrentUser()?.is_admin || 
                   document.getElementById('adminBadge')?.style.display === 'inline-block';
    navAdminLink.style.display = isAdmin ? 'inline' : 'none';
  }
  
  // Bind view-as button
  const viewAsBtn = document.getElementById('viewAsBtn');
  if (viewAsBtn && window.ViewAsModule) {
    viewAsBtn.addEventListener('click', () => {
      if (typeof window.ViewAsModule.openModal === 'function') {
        window.ViewAsModule.openModal();
      }
    });
  }
  
  // Bind logout button (handle both rota and requests structures)
  const logoutBtn = document.getElementById('logoutBtn');
  const userLogoutBtn = document.getElementById('userLogout');
  const logoutTarget = logoutBtn || userLogoutBtn;
  
  if (logoutTarget) {
    logoutTarget.addEventListener('click', async () => {
      if (typeof logout === 'function') {
        await logout();
      }
    });
  }
  
  // Bind notice bell
  const noticeBell = document.getElementById('noticeBell');
  if (noticeBell && window.noticeModalManager) {
    noticeBell.addEventListener('click', () => {
      window.noticeModalManager.openNoticeAllModal();
    });
  }
}

// Navigation functions (exported globally)
function navigateToRequests() {
  window.location.href = 'requests.html';
}

function navigateToRota() {
  window.location.href = 'rota.html';
}

function navigateToAdmin() {
  window.location.href = 'admin.html';
}

function goToFullAdmin() {
  window.location.href = 'admin.html';
}

// Initialize nav bar when ready
document.addEventListener('DOMContentLoaded', () => {
  // Small delay to let other modules initialize
  setTimeout(() => {
    initializeNavBar();
  }, 100);
});


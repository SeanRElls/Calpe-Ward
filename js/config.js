/**
 * =========================================================================
 * CALPE WARD REQUESTS - CONFIGURATION
 * =========================================================================
 * 
 * Central configuration file containing:
 * - Supabase connection credentials
 * - Application constants
 * - Business rules and limits
 * 
 * SECURITY NOTE:
 * The anon key shown here is safe to expose in client-side code.
 * It only allows row-level security policies you've defined in Supabase.
 * Never expose service_role keys in frontend code.
 * 
 * Last updated: January 2026
 * =========================================================================
 */


/* =========================================================================
   SUPABASE CONNECTION
   ========================================================================= */

/**
 * Supabase project URL and anon key
 */
const SUPABASE_URL = "https://pxpjxyfcydiasrycpbfp.supabase.co";
const SUPABASE_ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB4cGp4eWZjeWRpYXNyeWNwYmZwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg1NjE3OTAsImV4cCI6MjA4NDEzNzc5MH0.TEmgJEJGNFtBYyNWBnMiHycGv9jT5Gt_ImnH9zHXo88";

// Always set globals so clients have key available
window.SUPABASE_URL = SUPABASE_URL;
window.SUPABASE_ANON = SUPABASE_ANON;

/**
 * Initialize Supabase client
 * This object is used throughout the app for all database operations
 */
// Avoid redeclaring if config.js is included multiple times
window.supabaseClient = window.supabase.createClient(window.SUPABASE_URL, window.SUPABASE_ANON, {
   global: {
      headers: {
        apikey: window.SUPABASE_ANON,
        Authorization: `Bearer ${window.SUPABASE_ANON}`
      }
   }
});

// Do not create additional globals; use window.supabaseClient everywhere


/* =========================================================================
   APPLICATION CONSTANTS
   ========================================================================= */

/**
 * Local storage key for persisting logged-in user ID
 * Allows auto-login on page reload
 */
if (typeof window.STORAGE_KEY === 'undefined') {
   window.STORAGE_KEY = "calpeward.loggedInUserId";
}

/**
 * Maximum number of shift requests allowed per user per week
 * Users can enter up to 5 different requests across 7 days
 */
if (typeof window.MAX_REQUESTS_PER_WEEK === 'undefined') {
   window.MAX_REQUESTS_PER_WEEK = 5;
}

/**
 * Number of weeks displayed in the rota window
 * Shows 5 weeks at a time (standard shift planning period)
 */
if (typeof window.WINDOW_WEEKS === 'undefined') {
   window.WINDOW_WEEKS = 5;
}


/* =========================================================================
   EXPORT (if using modules in the future)
   ========================================================================= */

/**
 * For future module support, you can export these:
 * 
 * export {
 *   SUPABASE_URL,
 *   SUPABASE_ANON,
 *   supabaseClient,
 *   STORAGE_KEY,
 *   MAX_REQUESTS_PER_WEEK,
 *   WINDOW_WEEKS
 * };
 */

// Expose to window for cross-file access
// Ensure globals remain set if this file is re-run
window.SUPABASE_URL = window.SUPABASE_URL;
window.SUPABASE_ANON = window.SUPABASE_ANON;
window.STORAGE_KEY = window.STORAGE_KEY;

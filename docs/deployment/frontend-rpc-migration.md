/**
 * MIGRATION PATCH GUIDE: Token-Only RPCs
 * =======================================
 * 
 * This document lists all RPC call changes needed in frontend JS files.
 * 
 * PATTERN 1 - Staff functions (token-only):
 * OLD: rpc('function_name', { p_user_id: userId, p_pin: pin, ...args })
 * NEW: rpc('function_name', { p_token: token, ...args })
 * 
 * PATTERN 2 - Admin functions (token-based with is_admin bypass):
 * OLD: rpc('admin_function', { p_admin_id: adminId, p_pin: pin, ...args })
 * NEW: rpc('admin_function', { p_token: token, ...args })
 * 
 * =======================================
 * CHANGES BY FILE
 * =======================================
 */

// swap-functions.js
// -----------------
// Line 24: adminExecuteShiftSwap RPC
// OLD:
//   rpc("admin_execute_shift_swap", {
//     p_admin_id: window.currentUser.id,
//     p_pin: pin,
//     p_initiator_user_id: window.activeCell.userId,
//     p_initiator_shift_date: window.activeCell.date,
//     p_counterparty_user_id: counterpartyUserId,
//     p_counterparty_shift_date: counterpartyDate
//   })
// NEW:
//   rpc("admin_execute_shift_swap", {
//     p_token: window.currentToken,
//     p_initiator_user_id: window.activeCell.userId,
//     p_initiator_shift_date: window.activeCell.date,
//     p_counterparty_user_id: counterpartyUserId,
//     p_counterparty_shift_date: counterpartyDate
//   })

// Line 60: staffRequestShiftSwap RPC
// OLD:
//   rpc("staff_request_shift_swap", {
//     p_user_id: window.currentUser.id,
//     p_initiator_shift_date: window.activeCell.date,
//     p_counterparty_user_id: counterpartyUserId,
//     p_counterparty_shift_date: counterpartyDate
//   })
// NEW:
//   rpc("staff_request_shift_swap", {
//     p_token: window.currentToken,
//     p_initiator_shift_date: window.activeCell.date,
//     p_counterparty_user_id: counterpartyUserId,
//     p_counterparty_shift_date: counterpartyDate
//   })

// Line 97: staffRespondToSwapRequest RPC
// OLD:
//   rpc("staff_respond_to_swap_request", {
//     p_user_id: window.currentUser.id,
//     p_swap_request_id: swapRequestId,
//     p_response: response
//   })
// NEW:
//   rpc("staff_respond_to_swap_request", {
//     p_token: window.currentToken,
//     p_swap_request_id: swapRequestId,
//     p_response: response
//   })

// app.js
// ------
// Line 424: fetchWeekComments
// OLD: get_week_comments(p_week_id, p_user_id, p_pin)
// NEW: get_week_comments(p_week_id, p_token)
// NOTE: get_week_comments signature wasn't changed in our migration (uses PIN still)
// But should be updated to use token eventually

// Line 441: upsertWeekComment
// OLD: upsert_week_comment(p_week_id, p_user_id, p_pin, p_comment)
// NEW: Not changed in migration (still uses PIN)

// Line 896: admin_unlock_request_cell
// OLD:
//   rpc("admin_unlock_request_cell", {
//     p_admin_id: currentUser.id,
//     p_pin: pin,
//     p_target_user_id: targetUserId,
//     p_date: date
//   })
// NEW:
//   rpc("admin_unlock_request_cell", {
//     p_token: currentToken,
//     p_target_user_id: targetUserId,
//     p_date: date
//   })

// Line 920: admin_lock_request_cell
// OLD:
//   rpc("admin_lock_request_cell", {
//     p_admin_id: currentUser.id,
//     p_pin: pin,
//     p_target_user_id: targetUserId,
//     p_date: date,
//     p_reason_en: ...,
//     p_reason_es: ...
//   })
// NEW:
//   rpc("admin_lock_request_cell", {
//     p_token: currentToken,
//     p_target_user_id: targetUserId,
//     p_date: date,
//     p_reason_en: ...,
//     p_reason_es: ...
//   })

// Line 1108: set_user_language
// OLD: set_user_language(p_user_id, p_pin, p_lang)
// NOTE: Not changed in migration (uses PIN)

// Line 1149: verify_user_pin
// NOTE: Still needed for PIN verification before login/PIN change

// Line 1157: change_user_pin
// NOTE: Still needed (uses old_pin for verification)

// Line 1472/1881: admin_get_notice_acks
// OLD: rpc("admin_get_notice_acks", { p_notice_id: noticeId })
// NOTE: Function signature not in our migration - needs token guard added
// NEW: rpc("admin_get_notice_acks", { p_token: currentToken, p_notice_id: noticeId })

// Line 1490: ack_notice (implicit in refreshNotices, see below)

// Line 1981: ack_notice
// OLD:
//   rpc("ack_notice", {
//     p_notice_id: noticeId,
//     p_user_id: currentUser.id,
//     p_version: noticeVersion
//   })
// NEW:
//   rpc("ack_notice", {
//     p_token: currentToken,
//     p_notice_id: noticeId,
//     p_version: noticeVersion
//   })

// Line 2168: admin_approve_swap_request
// OLD:
//   rpc("admin_approve_swap_request", {
//     p_admin_id: currentUser.id,
//     p_pin: pin,
//     p_swap_request_id: id
//   })
// NEW:
//   rpc("admin_approve_swap_request", {
//     p_token: currentToken,
//     p_swap_request_id: id
//   })

// Line 2208: admin_decline_swap_request
// OLD:
//   rpc("admin_decline_swap_request", {
//     p_admin_id: currentUser.id,
//     p_pin: pin,
//     p_swap_request_id: id
//   })
// NEW:
//   rpc("admin_decline_swap_request", {
//     p_token: currentToken,
//     p_swap_request_id: id
//   })

// Line 2259: staff_respond_to_swap_request
// OLD:
//   rpc("staff_respond_to_swap_request", {
//     p_user_id: currentUser.id,
//     p_swap_request_id: swapRequestId,
//     p_response: response
//   })
// NEW:
//   rpc("staff_respond_to_swap_request", {
//     p_token: currentToken,
//     p_swap_request_id: swapRequestId,
//     p_response: response
//   })

// Line 2600: admin_upsert_notice
// OLD:
//   rpc("admin_upsert_notice", {
//     p_admin_id: currentUser.id,
//     p_pin: pin,
//     p_notice_id: ...,
//     p_title: ...,
//     p_body_en: ...,
//     p_body_es: ...,
//     p_target_all: ...,
//     p_target_roles: ...
//   })
// NEW:
//   rpc("admin_upsert_notice", {
//     p_token: currentToken,
//     p_notice_id: ...,
//     p_title: ...,
//     p_body_en: ...,
//     p_body_es: ...,
//     p_target_all: ...,
//     p_target_roles: ...
//   })

// Line 2622: admin_set_notice_active
// OLD:
//   rpc("admin_set_notice_active", {
//     p_admin_id: currentUser.id,
//     p_pin: pin,
//     p_notice_id: noticeId,
//     p_active: isActive
//   })
// NEW:
//   rpc("admin_set_notice_active", {
//     p_token: currentToken,
//     p_notice_id: noticeId,
//     p_active: isActive
//   })

// Line 2640: admin_delete_notice
// OLD:
//   rpc("admin_delete_notice", {
//     p_admin_id: currentUser.id,
//     p_pin: pin,
//     p_notice_id: noticeId
//   })
// NEW:
//   rpc("admin_delete_notice", {
//     p_token: currentToken,
//     p_notice_id: noticeId
//   })

// Line 2763: set_user_active
// OLD: rpc("set_user_active", { p_user_id, p_active })
// NOTE: Not changed in migration (legacy function)

// Line 3086/3109: admin_upsert_user
// OLD:
//   rpc("admin_upsert_user", {
//     p_user_id: userId,
//     p_name: ...,
//     p_role_id: ...
//   })
// NEW: (Signature stays same - only adds token guard in DB)

// Line 3336: admin_set_week_open_flags
// OLD:
//   rpc("admin_set_week_open_flags", {
//     p_admin_id: currentUser.id,
//     p_pin: pin,
//     p_week_id: weekId,
//     p_open: open,
//     p_open_after_close: openAfterClose
//   })
// NEW:
//   rpc("admin_set_week_open_flags", {
//     p_token: currentToken,
//     p_week_id: weekId,
//     p_open: open,
//     p_open_after_close: openAfterClose
//   })

// Line 3361: admin_set_active_period
// OLD:
//   rpc("admin_set_active_period", {
//     p_admin_id: currentUser.id,
//     p_pin: pin,
//     p_period_id: periodId
//   })
// NEW:
//   rpc("admin_set_active_period", {
//     p_token: currentToken,
//     p_period_id: periodId
//   })

// Line 3375: admin_toggle_hidden_period
// OLD:
//   rpc("admin_toggle_hidden_period", {
//     p_admin_id: currentUser.id,
//     p_pin: pin,
//     p_period_id: periodId
//   })
// NEW:
//   rpc("admin_toggle_hidden_period", {
//     p_token: currentToken,
//     p_period_id: periodId
//   })

// Line 3397: admin_create_five_week_period (NOT in our migration - skip for now)

// Line 3506: admin_set_period_closes_at
// OLD:
//   rpc("admin_set_period_closes_at", {
//     p_admin_id: currentUser.id,
//     p_pin: pin,
//     p_period_id: periodId,
//     p_closes_at: closesAt
//   })
// NEW:
//   rpc("admin_set_period_closes_at", {
//     p_token: currentToken,
//     p_period_id: periodId,
//     p_closes_at: closesAt
//   })

// Line 4138: admin_set_request_cell
// OLD:
//   rpc("admin_set_request_cell", {
//     p_admin_id: currentUser.id,
//     p_pin: pin,
//     p_target_user_id: userId,
//     p_date: date,
//     p_value: value,
//     p_important_rank: importantRank
//   })
// NEW:
//   rpc("admin_set_request_cell", {
//     p_token: currentToken,
//     p_target_user_id: userId,
//     p_date: date,
//     p_value: value,
//     p_important_rank: importantRank
//   })

// Line 4151: set_request_cell
// OLD:
//   rpc("set_request_cell", {
//     p_user_id: userId,
//     p_pin: pin,
//     p_date: date,
//     p_value: value,
//     p_important_rank: importantRank
//   })
// NEW:
//   rpc("set_request_cell", {
//     p_token: currentToken,
//     p_date: date,
//     p_value: value,
//     p_important_rank: importantRank
//   })

// Line 4173: admin_clear_request_cell
// OLD:
//   rpc("admin_clear_request_cell", {
//     p_admin_id: currentUser.id,
//     p_pin: pin,
//     p_target_user_id: userId,
//     p_date: date
//   })
// NEW:
//   rpc("admin_clear_request_cell", {
//     p_token: currentToken,
//     p_target_user_id: userId,
//     p_date: date
//   })

// Line 4184: clear_request_cell
// OLD:
//   rpc("clear_request_cell", {
//     p_user_id: userId,
//     p_pin: pin,
//     p_date: date
//   })
// NEW:
//   rpc("clear_request_cell", {
//     p_token: currentToken,
//     p_date: date
//   })

// Line 5680: admin_execute_shift_swap (duplicate in main code)
// Same as swap-functions.js

// Line 5704: staff_request_shift_swap (duplicate in main code)
// Same as swap-functions.js

// Line 5722: staff_respond_to_swap_request (duplicate in main code)
// Same as swap-functions.js

// admin.js
// --------
// Similar changes for all admin_* RPC calls
// OLD: p_admin_id + p_pin
// NEW: p_token

// notifications-shared.js
// -----------------------
// Need to check for any RPC calls

// shift-functions.js
// ------------------
// Need to check for any RPC calls

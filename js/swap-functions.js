// Swap Functions Module
// Provides RPC wrappers for shift swap operations (admin direct + staff proposed)
// Used by both index.html and rota.html

// These functions assume window.currentUser and window.supabaseClient are available

async function adminExecuteShiftSwap(counterpartyUserId, counterpartyDate){
  if (!window.currentUser?.is_admin) throw new Error("Admin only");
  if (!window.activeCell) throw new Error("No active cell");

  const pin = typeof getSessionPinOrThrow === "function" ? getSessionPinOrThrow() : null;
  const periodId = window.currentPeriod?.id;
  if (!periodId) throw new Error("No active period");

  const { data, error } = await window.supabaseClient.rpc("admin_execute_shift_swap", {
    p_token: window.currentToken,
    p_initiator_user_id: window.activeCell.userId,
    p_initiator_shift_date: window.activeCell.date,
    p_counterparty_user_id: counterpartyUserId,
    p_counterparty_shift_date: counterpartyDate
  });

  if (error) throw error;
  if (!data[0]?.success) throw new Error(data[0]?.error_message || "Swap failed");

  return data[0];
}

async function staffRequestShiftSwap(counterpartyUserId, counterpartyDate){
  if (!window.currentUser || window.currentUser.is_admin) throw new Error("Staff only");
  if (!window.activeCell) throw new Error("No active cell");

  const periodId = window.currentPeriod?.id;
  if (!periodId) throw new Error("No active period");

  const { data, error } = await window.supabaseClient.rpc("staff_request_shift_swap", {
    p_token: window.currentToken,
    p_initiator_shift_date: window.activeCell.date,
    p_counterparty_user_id: counterpartyUserId,
    p_counterparty_shift_date: counterpartyDate
  });

  if (error) throw error;
  if (!data[0]?.success) throw new Error(data[0]?.error_message || "Request failed");

  return data[0];
}

async function staffRespondToSwapRequest(swapRequestId, response){
  if (!window.currentUser || window.currentUser.is_admin) throw new Error("Staff only");
  if (!['accepted', 'declined', 'ignored'].includes(response)) throw new Error("Invalid response");

  const { data, error } = await window.supabaseClient.rpc("staff_respond_to_swap_request", {
    p_token: window.currentToken,
    p_swap_request_id: swapRequestId,
    p_response: response
  });

  if (error) throw error;
  if (!data[0]?.success) throw new Error(data[0]?.error_message || "Response failed");

  return data[0];
}

// Expose to window
window.adminExecuteShiftSwap = adminExecuteShiftSwap;
window.staffRequestShiftSwap = staffRequestShiftSwap;
window.staffRespondToSwapRequest = staffRespondToSwapRequest;

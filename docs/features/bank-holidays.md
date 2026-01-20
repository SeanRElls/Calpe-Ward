# Bank Holidays Feature - Implementation Guide

## Overview
Bank holidays are now fully integrated into the rota system. They appear with a distinct visual style on both the rota and requests pages, making it clear which dates are holidays.

## Database Schema
- **Table**: `public.bank_holidays`
- **Columns**:
  - `id` (UUID): Primary key
  - `year` (INTEGER): Year of the bank holiday (e.g., 2026)
  - `holiday_date` (DATE): The specific date
  - `name` (TEXT): Holiday name (e.g., "Christmas Day")
  - `is_active` (BOOLEAN): Soft delete flag
  - `created_at` (TIMESTAMP): When the record was created
  - `created_by` (UUID): User who created it

## RPCs Available

### `rpc_list_bank_holidays(p_year INTEGER)`
Returns all active bank holidays for a given year, ordered by date.

### `rpc_add_bank_holiday(p_token UUID, p_year INTEGER, p_date DATE, p_name TEXT)`
Admin-only RPC to add a new bank holiday. Validates:
- Token is valid
- User is admin
- Year is between 2000 and 2100
- Date matches the specified year
- Holiday name is provided

### `rpc_delete_bank_holiday(p_token UUID, p_id UUID)`
Admin-only RPC to soft-delete a bank holiday (sets `is_active = FALSE`).

### `rpc_get_all_bank_holidays(p_start_year, p_end_year)`
Bulk fetch for multiple years (used by frontend for caching).

## Frontend Implementation

### Rota Display (rota.html)
1. **Initialization**: On page load, `loadBankHolidays()` fetches all bank holidays and caches them by date string (YYYY-MM-DD format)
2. **Cell Styling**: Cells for bank holiday dates receive the `.bank-holiday` CSS class
3. **Visual**: Cells display with `--bank-holiday` color (#e8e0d0 - light tan/beige)

### Key Functions
- `loadBankHolidays()`: Loads holidays from DB at startup
- `isBankHoliday(date)`: Checks if a given date is a holiday
- `getBankHolidayName(date)`: Returns the holiday name (if needed)

## Admin Panel (admin.html)

### Bank Holidays Section
Located in the admin navigation (between Non‑Staff and Permissions).

#### Features:
1. **Year Selection**: Dropdown to select 2026-2030
2. **Add Holiday**:
   - Date input (must match selected year)
   - Holiday name (text input)
   - Add button
3. **List View**: Shows all holidays for the selected year with delete buttons

#### Usage:
1. Select the year from the dropdown
2. Enter a date and name
3. Click "Add"
4. Holidays appear in the list below
5. Click "Delete" to remove a holiday

## Styling

### CSS Variables
- `--bank-holiday: #e8e0d0` (light tan/beige background)

### CSS Classes
- `td.cell.bank-holiday`: Applied to rota cells on bank holiday dates

## Date Handling
- Dates are stored as DATE in PostgreSQL
- Frontend converts to YYYY-MM-DD format for comparison
- Date picker in admin ensures correct year matching
- Display uses localized format (e.g., "Mon, 25 Dec 2026")

## Audit & Security
- All add/delete operations logged to `audit_logs`
- Admin-only access enforced via SECURITY DEFINER RPCs
- Session validation on every operation

## Future Enhancements
- Bulk import bank holidays from template
- Different bank holidays by region/location
- Automatic staffing adjustments on bank holidays
- Holiday swaps/coverage notifications

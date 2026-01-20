/**
 * ICS Calendar Feed Edge Function
 * 
 * Generates RFC 5545 compliant iCalendar feed for published shifts
 * Authenticates via calendar token (not session token)
 * 
 * Usage: GET /functions/v1/ics?token=<calendar_token>
 * 
 * Returns:
 * - 200: text/calendar with VCALENDAR
 * - 401: Invalid/revoked token
 * - 500: Server error
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// CORS headers for calendar clients
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ShiftRow {
  assignment_id: number;
  shift_date: string;
  shift_code: string;
  shift_label: string;
  start_time: string;
  end_time: string;
  hours_value: number;
}

/**
 * Escape text for ICS format per RFC 5545
 */
function escapeICSText(text: string): string {
  return text
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\n/g, "\\n");
}

/**
 * Format datetime for ICS (UTC): YYYYMMDDTHHMMSSZ
 */
function formatICSDateTime(date: Date): string {
  const pad = (n: number) => n.toString().padStart(2, "0");
  return (
    date.getUTCFullYear() +
    pad(date.getUTCMonth() + 1) +
    pad(date.getUTCDate()) +
    "T" +
    pad(date.getUTCHours()) +
    pad(date.getUTCMinutes()) +
    pad(date.getUTCSeconds()) +
    "Z"
  );
}

/**
 * Format time for display: HH:MM
 */
function formatTimeDisplay(timeStr: string): string {
  // timeStr format: "HH:MM:SS" or "HH:MM"
  return timeStr.substring(0, 5);
}

/**
 * Fold long lines per RFC 5545 (max 75 octets per line)
 */
function foldLine(line: string): string {
  const maxLen = 75;
  if (line.length <= maxLen) return line;
  
  let result = line.substring(0, maxLen) + "\r\n";
  let remaining = line.substring(maxLen);
  
  while (remaining.length > 0) {
    const chunk = remaining.substring(0, maxLen - 1); // -1 for leading space
    result += " " + chunk + "\r\n";
    remaining = remaining.substring(maxLen - 1);
  }
  
  return result.trimEnd() + "\r\n";
}

/**
 * Build VEVENT from shift data
 */
function buildVEvent(shift: ShiftRow): string {
  // Combine date + time to create proper datetime
  const shiftDate = new Date(shift.shift_date + "T00:00:00Z");
  const [startHour, startMin] = shift.start_time.split(":").map(Number);
  const [endHour, endMin] = shift.end_time.split(":").map(Number);
  
  // Start datetime
  const dtStart = new Date(shiftDate);
  dtStart.setUTCHours(startHour, startMin, 0, 0);
  
  // End datetime (handle overnight shifts)
  const dtEnd = new Date(shiftDate);
  dtEnd.setUTCHours(endHour, endMin, 0, 0);
  if (endHour < startHour) {
    // Overnight shift - add 1 day to end
    dtEnd.setUTCDate(dtEnd.getUTCDate() + 1);
  }
  
  // Stable UID for updates
  const uid = `shift-${shift.assignment_id}@calpeward`;
  
  // Summary: "CODE - LABEL"
  const summary = escapeICSText(`${shift.shift_code} - ${shift.shift_label}`);
  
  // Description: Hours with times
  const startTimeDisplay = formatTimeDisplay(shift.start_time);
  const endTimeDisplay = formatTimeDisplay(shift.end_time);
  const description = escapeICSText(`Hours: ${startTimeDisplay} – ${endTimeDisplay}`);
  
  // Current timestamp
  const dtstamp = formatICSDateTime(new Date());
  
  // Build VEVENT
  let vevent = "";
  vevent += "BEGIN:VEVENT\r\n";
  vevent += foldLine(`UID:${uid}`);
  vevent += foldLine(`DTSTAMP:${dtstamp}`);
  vevent += foldLine(`DTSTART:${formatICSDateTime(dtStart)}`);
  vevent += foldLine(`DTEND:${formatICSDateTime(dtEnd)}`);
  vevent += foldLine(`SUMMARY:${summary}`);
  vevent += foldLine(`DESCRIPTION:${description}`);
  vevent += foldLine("LOCATION:Calpe Ward");
  vevent += foldLine("STATUS:CONFIRMED");
  vevent += foldLine("TRANSP:OPAQUE");
  vevent += "END:VEVENT\r\n";
  
  return vevent;
}

/**
 * Build complete VCALENDAR
 */
function buildVCalendar(shifts: ShiftRow[]): string {
  let ics = "";
  
  // Calendar headers
  ics += "BEGIN:VCALENDAR\r\n";
  ics += "VERSION:2.0\r\n";
  ics += "PRODID:-//Calpe Ward//Shift Calendar//EN\r\n";
  ics += "CALSCALE:GREGORIAN\r\n";
  ics += "METHOD:PUBLISH\r\n";
  ics += foldLine("X-WR-CALNAME:Calpe Ward Shifts");
  ics += foldLine("X-WR-CALDESC:Your published shift assignments");
  ics += foldLine("X-WR-TIMEZONE:Europe/Madrid");
  
  // Add each shift as VEVENT
  for (const shift of shifts) {
    ics += buildVEvent(shift);
  }
  
  ics += "END:VCALENDAR\r\n";
  
  return ics;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Parse token from query string
    const url = new URL(req.url);
    const token = url.searchParams.get("token");
    
    if (!token) {
      return new Response("Missing token parameter", {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "text/plain" },
      });
    }
    
    // Create Supabase client with service role for RPC call
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    });
    
    // Call RPC to get published shifts
    const { data: shifts, error } = await supabase.rpc(
      "get_published_shifts_for_calendar",
      { p_calendar_token: token }
    );
    
    if (error) {
      console.error("RPC error:", error);
      
      // Check if it's a token validation error
      if (error.message?.includes("Invalid or revoked")) {
        return new Response("Invalid or revoked calendar token", {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "text/plain" },
        });
      }
      
      return new Response("Failed to fetch shifts", {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "text/plain" },
      });
    }
    
    // Build ICS calendar
    const icsContent = buildVCalendar(shifts || []);
    
    // Return with proper content type and caching
    return new Response(icsContent, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "text/calendar; charset=utf-8",
        "Content-Disposition": 'attachment; filename="calpe-ward-shifts.ics"',
        "Cache-Control": "private, max-age=300", // 5 minutes
      },
    });
  } catch (error) {
    console.error("Edge function error:", error);
    return new Response("Internal server error", {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "text/plain" },
    });
  }
});

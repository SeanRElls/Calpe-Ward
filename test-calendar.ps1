#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test calendar subscription implementation

.DESCRIPTION
    Validates that the calendar subscription feature is deployed and working correctly.
    Tests database schema, RPCs, Edge Function, and ICS format.

.PARAMETER ProjectUrl
    Your Supabase project URL (e.g., https://xxxxx.supabase.co)

.PARAMETER AnonKey
    Your Supabase anon key

.PARAMETER SessionToken
    Current user session token (from window.currentToken in browser)

.EXAMPLE
    .\test-calendar.ps1 -ProjectUrl "https://pxpjxyfcydiasrycpbfp.supabase.co" `
                        -AnonKey "your-anon-key" `
                        -SessionToken "your-session-token"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectUrl,
    
    [Parameter(Mandatory=$true)]
    [string]$AnonKey,
    
    [Parameter(Mandatory=$true)]
    [string]$SessionToken
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Calendar Subscription Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Test counter
$testNum = 1
$passCount = 0
$failCount = 0

function Test-Step {
    param(
        [string]$Name,
        [scriptblock]$Test
    )
    
    Write-Host "[$testNum] $Name..." -NoNewline
    
    try {
        $result = & $Test
        if ($result -eq $true -or $result -eq $null) {
            Write-Host " ✅ PASS" -ForegroundColor Green
            $script:passCount++
        } else {
            Write-Host " ❌ FAIL: $result" -ForegroundColor Red
            $script:failCount++
        }
    } catch {
        Write-Host " ❌ FAIL: $($_.Exception.Message)" -ForegroundColor Red
        $script:failCount++
    }
    
    $script:testNum++
}

# Test 1: Generate Calendar Token
$calendarToken = $null
Test-Step "Generate calendar token" {
    $body = @{
        p_token = $SessionToken
    } | ConvertTo-Json
    
    $response = Invoke-RestMethod `
        -Method POST `
        -Uri "$ProjectUrl/rest/v1/rpc/generate_calendar_token" `
        -Headers @{
            "apikey" = $AnonKey
            "Authorization" = "Bearer $AnonKey"
            "Content-Type" = "application/json"
        } `
        -Body $body
    
    if ($response.success -and $response.token) {
        $script:calendarToken = $response.token
        Write-Host "    Token: $($response.token.Substring(0, 20))..." -ForegroundColor DarkGray
        return $true
    } else {
        return "Invalid response: $($response | ConvertTo-Json)"
    }
}

# Test 2: Fetch ICS Feed
$icsContent = $null
Test-Step "Fetch ICS feed with valid token" {
    if (-not $script:calendarToken) {
        return "No token from previous test"
    }
    
    $response = Invoke-WebRequest `
        -Uri "$ProjectUrl/functions/v1/ics?token=$script:calendarToken" `
        -Method GET
    
    if ($response.StatusCode -eq 200) {
        $script:icsContent = $response.Content
        
        # Check content type
        $contentType = $response.Headers["Content-Type"]
        if ($contentType -notlike "*text/calendar*") {
            return "Wrong content type: $contentType"
        }
        
        # Check for basic ICS structure
        if ($script:icsContent -notmatch "BEGIN:VCALENDAR") {
            return "Missing BEGIN:VCALENDAR"
        }
        if ($script:icsContent -notmatch "END:VCALENDAR") {
            return "Missing END:VCALENDAR"
        }
        
        Write-Host "    Content-Type: $contentType" -ForegroundColor DarkGray
        Write-Host "    Size: $($script:icsContent.Length) bytes" -ForegroundColor DarkGray
        
        return $true
    } else {
        return "HTTP $($response.StatusCode)"
    }
}

# Test 3: Validate ICS Format
Test-Step "Validate ICS format" {
    if (-not $script:icsContent) {
        return "No ICS content from previous test"
    }
    
    $required = @(
        "VERSION:2.0",
        "PRODID:",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH"
    )
    
    foreach ($field in $required) {
        if ($script:icsContent -notmatch $field) {
            return "Missing required field: $field"
        }
    }
    
    # Check for CRLF line endings
    if ($script:icsContent -notmatch "\r\n") {
        return "Missing CRLF line endings"
    }
    
    return $true
}

# Test 4: Validate Event Structure
Test-Step "Validate VEVENT structure" {
    if (-not $script:icsContent) {
        return "No ICS content"
    }
    
    # Extract first VEVENT
    if ($script:icsContent -match "BEGIN:VEVENT.*?END:VEVENT") {
        $vevent = $Matches[0]
        
        $required = @(
            "UID:",
            "DTSTAMP:",
            "DTSTART:",
            "DTEND:",
            "SUMMARY:",
            "DESCRIPTION:",
            "LOCATION:Calpe Ward"
        )
        
        foreach ($field in $required) {
            if ($vevent -notmatch $field) {
                return "VEVENT missing: $field"
            }
        }
        
        # Check SUMMARY format: "CODE - LABEL"
        if ($vevent -match "SUMMARY:(.+)") {
            $summary = $Matches[1]
            if ($summary -notmatch ".+ - .+") {
                return "SUMMARY not in 'CODE - LABEL' format: $summary"
            }
            Write-Host "    Sample SUMMARY: $summary" -ForegroundColor DarkGray
        }
        
        # Check UID format: "shift-<id>@calpeward"
        if ($vevent -match "UID:(.+)") {
            $uid = $Matches[1]
            if ($uid -notmatch "shift-\d+@calpeward") {
                return "UID not in expected format: $uid"
            }
            Write-Host "    Sample UID: $uid" -ForegroundColor DarkGray
        }
        
        return $true
    } else {
        return "No VEVENT found in calendar"
    }
}

# Test 5: Test Invalid Token
Test-Step "Reject invalid token" {
    $response = Invoke-WebRequest `
        -Uri "$ProjectUrl/functions/v1/ics?token=invalid-token-12345" `
        -Method GET `
        -SkipHttpErrorCheck
    
    if ($response.StatusCode -eq 401) {
        Write-Host "    Correctly returned 401 Unauthorized" -ForegroundColor DarkGray
        return $true
    } else {
        return "Expected 401, got $($response.StatusCode)"
    }
}

# Test 6: Test Missing Token
Test-Step "Reject missing token" {
    $response = Invoke-WebRequest `
        -Uri "$ProjectUrl/functions/v1/ics" `
        -Method GET `
        -SkipHttpErrorCheck
    
    if ($response.StatusCode -eq 401) {
        Write-Host "    Correctly returned 401 Unauthorized" -ForegroundColor DarkGray
        return $true
    } else {
        return "Expected 401, got $($response.StatusCode)"
    }
}

# Test 7: Verify Token in Database
Test-Step "Verify token stored in database" {
    $body = @{} | ConvertTo-Json
    
    $response = Invoke-RestMethod `
        -Method GET `
        -Uri "$ProjectUrl/rest/v1/calendar_tokens?select=id,created_at,last_used_at,revoked_at&revoked_at=is.null" `
        -Headers @{
            "apikey" = $AnonKey
            "Authorization" = "Bearer $AnonKey"
        }
    
    if ($response -and $response.Count -gt 0) {
        $token = $response[0]
        Write-Host "    Token ID: $($token.id)" -ForegroundColor DarkGray
        Write-Host "    Created: $($token.created_at)" -ForegroundColor DarkGray
        Write-Host "    Last used: $($token.last_used_at)" -ForegroundColor DarkGray
        return $true
    } else {
        return "No active tokens found"
    }
}

# Test 8: Revoke Token
Test-Step "Revoke calendar token" {
    $body = @{
        p_token = $SessionToken
    } | ConvertTo-Json
    
    $response = Invoke-RestMethod `
        -Method POST `
        -Uri "$ProjectUrl/rest/v1/rpc/revoke_calendar_token" `
        -Headers @{
            "apikey" = $AnonKey
            "Authorization" = "Bearer $AnonKey"
            "Content-Type" = "application/json"
        } `
        -Body $body
    
    if ($response.success) {
        Write-Host "    Revoked $($response.revoked_count) token(s)" -ForegroundColor DarkGray
        return $true
    } else {
        return "Revoke failed: $($response | ConvertTo-Json)"
    }
}

# Test 9: Verify Revoked Token Rejected
Test-Step "Verify revoked token rejected" {
    if (-not $script:calendarToken) {
        return "No token to test"
    }
    
    $response = Invoke-WebRequest `
        -Uri "$ProjectUrl/functions/v1/ics?token=$script:calendarToken" `
        -Method GET `
        -SkipHttpErrorCheck
    
    if ($response.StatusCode -eq 401) {
        Write-Host "    Correctly rejected revoked token" -ForegroundColor DarkGray
        return $true
    } else {
        return "Revoked token still works! Status: $($response.StatusCode)"
    }
}

# Test Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Results" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Red" })
Write-Host "Total:  $($passCount + $failCount)" -ForegroundColor Cyan
Write-Host ""

if ($failCount -eq 0) {
    Write-Host "✅ All tests passed! Calendar subscription is working correctly." -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ Some tests failed. Check the output above for details." -ForegroundColor Red
    exit 1
}

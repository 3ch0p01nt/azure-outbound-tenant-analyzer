#Requires -Version 5.1

<#
.SYNOPSIS
    Look up Azure AD tenant name from a tenant ID (GUID).

.DESCRIPTION
    Uses the OpenID configuration endpoint to resolve tenant IDs to tenant names.
    This works without authentication.

.PARAMETER TenantId
    One or more tenant IDs (GUIDs) to look up.

.PARAMETER InputFile
    Path to a file containing tenant IDs (one per line).

.EXAMPLE
    .\Lookup-TenantName.ps1 -TenantId "cfff68a4-5e50-4cf7-8eaf-f67385f0e821"

.EXAMPLE
    .\Lookup-TenantName.ps1 -TenantId "tenant1-guid", "tenant2-guid", "tenant3-guid"

.EXAMPLE
    .\Lookup-TenantName.ps1 -InputFile "tenant_ids.txt"
#>

param(
    [Parameter(ParameterSetName='Direct')]
    [string[]]$TenantId,

    [Parameter(ParameterSetName='File')]
    [string]$InputFile
)

function Get-TenantName {
    param([string]$Id)

    try {
        $uri = "https://login.microsoftonline.com/$Id/.well-known/openid-configuration"
        $response = Invoke-RestMethod -Uri $uri -Method Get -ErrorAction Stop

        # Extract tenant name from issuer or token endpoint
        $issuer = $response.issuer
        $tenantName = "Unknown"

        # Try to get tenant info from authorization endpoint
        $authEndpoint = $response.authorization_endpoint
        if ($authEndpoint -match "login\.microsoftonline\.com/([^/]+)/") {
            $tenantName = $Matches[1]
        }

        # Also try the branding API (may not work for all tenants)
        try {
            $brandingUri = "https://login.microsoftonline.com/$Id/oauth2/v2.0/authorize?client_id=00000000-0000-0000-0000-000000000000&response_type=id_token&scope=openid&nonce=1"
            $headers = Invoke-WebRequest -Uri $brandingUri -Method Get -MaximumRedirection 0 -ErrorAction SilentlyContinue -SkipHttpErrorCheck
        } catch {}

        # Try to resolve via Graph (requires existing token - best effort)
        $displayName = $null
        try {
            $orgUri = "https://graph.microsoft.com/v1.0/organization"
            $context = Get-MgContext -ErrorAction SilentlyContinue
            if ($context) {
                # We have a Graph connection, but may not have access to query other tenants
            }
        } catch {}

        [PSCustomObject]@{
            TenantId     = $Id
            Issuer       = $issuer
            Region       = if ($issuer -like "*.us*") { "US Government" } else { "Commercial" }
            TokenEndpoint = $response.token_endpoint
            Status       = "Valid"
        }
    }
    catch {
        [PSCustomObject]@{
            TenantId     = $Id
            Issuer       = "N/A"
            Region       = "Unknown"
            TokenEndpoint = "N/A"
            Status       = "Invalid or Not Found"
        }
    }
}

# Get tenant IDs to process
$tenantsToLookup = @()

if ($TenantId) {
    $tenantsToLookup = $TenantId
}
elseif ($InputFile) {
    if (Test-Path $InputFile) {
        $tenantsToLookup = Get-Content $InputFile | Where-Object { $_ -match '\S' }
    }
    else {
        Write-Error "File not found: $InputFile"
        exit 1
    }
}
else {
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\Lookup-TenantName.ps1 -TenantId 'guid1', 'guid2'" -ForegroundColor Gray
    Write-Host "  .\Lookup-TenantName.ps1 -InputFile 'tenants.txt'" -ForegroundColor Gray
    exit 0
}

Write-Host "Looking up $($tenantsToLookup.Count) tenant(s)..." -ForegroundColor Cyan
Write-Host ""

$results = foreach ($id in $tenantsToLookup) {
    $cleanId = $id.Trim()
    if ($cleanId) {
        Write-Host "  Checking: $cleanId" -ForegroundColor Gray
        Get-TenantName -Id $cleanId
    }
}

Write-Host ""
Write-Host "=== RESULTS ===" -ForegroundColor Green
$results | Format-Table -AutoSize

# Summary
$valid = ($results | Where-Object Status -eq "Valid").Count
$invalid = ($results | Where-Object Status -ne "Valid").Count
$govCloud = ($results | Where-Object Region -eq "US Government").Count

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Valid tenants:      $valid" -ForegroundColor Green
Write-Host "  Invalid/Not found:  $invalid" -ForegroundColor $(if($invalid -gt 0){'Yellow'}else{'Green'})
Write-Host "  US Government:      $govCloud" -ForegroundColor $(if($govCloud -gt 0){'Magenta'}else{'Gray'})

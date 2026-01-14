#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Reports

<#
.SYNOPSIS
    Find external tenants that YOUR USERS have authenticated TO (outbound access).

.DESCRIPTION
    This script queries Microsoft Graph sign-in logs to identify external tenants
    that your organization's users have accessed. This shows OUTBOUND cross-tenant
    activity - where your users are going, not who's coming in.

.PARAMETER Days
    Number of days to look back. Default is 30. Maximum is 30 for sign-in logs.

.PARAMETER ExportPath
    Optional path to export results to CSV.

.EXAMPLE
    .\Get-OutboundTenantAccess.ps1 -Days 7

.EXAMPLE
    .\Get-OutboundTenantAccess.ps1 -Days 30 -ExportPath "C:\Reports\OutboundAccess.csv"

.NOTES
    Required permissions:
    - AuditLog.Read.All
    - Directory.Read.All
#>

param(
    [int]$Days = 30,
    [string]$ExportPath
)

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "AuditLog.Read.All", "Directory.Read.All" -NoWelcome

# Get your tenant ID
$context = Get-MgContext
$myTenantId = $context.TenantId
Write-Host "Your Tenant ID: $myTenantId" -ForegroundColor Green
Write-Host "Looking for: External tenants YOUR users have accessed" -ForegroundColor Yellow

# Calculate date filter
$startDate = (Get-Date).AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
$filter = "createdDateTime ge $startDate"

Write-Host "Fetching sign-in logs from the last $Days days..." -ForegroundColor Cyan

# Get sign-in logs
$signInLogs = @()
$uri = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=$filter&`$top=999"

do {
    $response = Invoke-MgGraphRequest -Uri $uri -Method GET
    $signInLogs += $response.value
    $uri = $response.'@odata.nextLink'
    Write-Host "  Retrieved $($signInLogs.Count) records..." -ForegroundColor Gray
} while ($uri)

Write-Host "Total sign-in records retrieved: $($signInLogs.Count)" -ForegroundColor Green

# Filter for OUTBOUND access (Your users accessing external tenants)
# HomeTenantId = YOUR tenant, ResourceTenantId = EXTERNAL tenant
$outboundAccess = $signInLogs | Where-Object {
    $_.homeTenantId -eq $myTenantId -and
    $_.resourceTenantId -ne $myTenantId -and
    $_.resourceTenantId -ne $null -and
    $_.resourceTenantId -ne ""
}

Write-Host "Outbound external tenant accesses found: $($outboundAccess.Count)" -ForegroundColor Yellow

if ($outboundAccess.Count -eq 0) {
    Write-Host "`nNo outbound cross-tenant access found in the last $Days days." -ForegroundColor Green
    Write-Host "This means your users have not accessed resources in external tenants." -ForegroundColor Gray
    exit 0
}

# Group by external tenant (ResourceTenantId)
$tenantSummary = $outboundAccess | Group-Object -Property resourceTenantId | ForEach-Object {
    $tenantAccess = $_.Group
    $users = $tenantAccess | Select-Object -ExpandProperty userPrincipalName -Unique
    $apps = $tenantAccess | Select-Object -ExpandProperty appDisplayName -Unique
    $resources = $tenantAccess | Select-Object -ExpandProperty resourceDisplayName -Unique

    [PSCustomObject]@{
        ExternalTenantId = $_.Name
        AccessCount      = $_.Count
        UniqueUsers      = $users.Count
        Users            = ($users | Select-Object -First 5) -join "; "
        UniqueApps       = $apps.Count
        Applications     = ($apps | Select-Object -First 5) -join "; "
        Resources        = ($resources | Select-Object -First 5) -join "; "
        FirstAccess      = ($tenantAccess | Sort-Object createdDateTime | Select-Object -First 1).createdDateTime
        LastAccess       = ($tenantAccess | Sort-Object createdDateTime -Descending | Select-Object -First 1).createdDateTime
    }
} | Sort-Object AccessCount -Descending

# Display results
Write-Host "`n=== EXTERNAL TENANTS YOUR USERS HAVE ACCESSED ===" -ForegroundColor Cyan
$tenantSummary | Format-Table -AutoSize

# User summary - who's accessing external tenants
Write-Host "`n=== USERS WITH EXTERNAL TENANT ACCESS ===" -ForegroundColor Cyan
$userSummary = $outboundAccess | Group-Object -Property userPrincipalName | ForEach-Object {
    $userAccess = $_.Group
    $externalTenants = $userAccess | Select-Object -ExpandProperty resourceTenantId -Unique

    [PSCustomObject]@{
        UserPrincipalName     = $_.Name
        ExternalTenantsCount  = $externalTenants.Count
        TotalAccesses         = $_.Count
        ExternalTenants       = ($externalTenants | Select-Object -First 3) -join "; "
        LastAccess            = ($userAccess | Sort-Object createdDateTime -Descending | Select-Object -First 1).createdDateTime
    }
} | Sort-Object ExternalTenantsCount -Descending

$userSummary | Select-Object -First 15 | Format-Table -AutoSize

# Application summary
Write-Host "`n=== APPLICATIONS USED FOR EXTERNAL ACCESS ===" -ForegroundColor Cyan
$appSummary = $outboundAccess | Group-Object -Property appDisplayName | ForEach-Object {
    $appAccess = $_.Group
    $externalTenants = $appAccess | Select-Object -ExpandProperty resourceTenantId -Unique

    [PSCustomObject]@{
        ApplicationName       = $_.Name
        ExternalTenantsCount  = $externalTenants.Count
        AccessCount           = $_.Count
        UniqueUsers           = ($appAccess | Select-Object -ExpandProperty userPrincipalName -Unique).Count
    }
} | Sort-Object AccessCount -Descending

$appSummary | Select-Object -First 10 | Format-Table -AutoSize

# Detailed access log
Write-Host "`n=== DETAILED ACCESS LOG (Last 20) ===" -ForegroundColor Cyan
$detailedLogs = $outboundAccess | Select-Object `
    @{N='ExternalTenantId';E={$_.resourceTenantId}},
    @{N='UserPrincipalName';E={$_.userPrincipalName}},
    @{N='AppDisplayName';E={$_.appDisplayName}},
    @{N='ResourceDisplayName';E={$_.resourceDisplayName}},
    @{N='IPAddress';E={$_.ipAddress}},
    @{N='Status';E={if($_.status.errorCode -eq 0){'Success'}else{'Failed'}}},
    @{N='CreatedDateTime';E={$_.createdDateTime}} |
    Sort-Object CreatedDateTime -Descending

$detailedLogs | Select-Object -First 20 | Format-Table -AutoSize

# Export if path specified
if ($ExportPath) {
    Write-Host "`nExporting to $ExportPath..." -ForegroundColor Cyan

    $exportDir = Split-Path $ExportPath -Parent
    if ($exportDir -and !(Test-Path $exportDir)) {
        New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
    }

    # Export tenant summary
    $summaryPath = $ExportPath -replace '\.csv$', '_ExternalTenantSummary.csv'
    $tenantSummary | Export-Csv -Path $summaryPath -NoTypeInformation
    Write-Host "  External tenant summary exported to: $summaryPath" -ForegroundColor Green

    # Export user summary
    $userPath = $ExportPath -replace '\.csv$', '_UserSummary.csv'
    $userSummary | Export-Csv -Path $userPath -NoTypeInformation
    Write-Host "  User summary exported to: $userPath" -ForegroundColor Green

    # Export detailed logs
    $detailPath = $ExportPath -replace '\.csv$', '_DetailedLogs.csv'
    $detailedLogs | Export-Csv -Path $detailPath -NoTypeInformation
    Write-Host "  Detailed logs exported to: $detailPath" -ForegroundColor Green
}

# Summary statistics
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "  External tenants accessed:  $($tenantSummary.Count)" -ForegroundColor White
Write-Host "  Total outbound accesses:    $($outboundAccess.Count)" -ForegroundColor White
Write-Host "  Users with external access: $($userSummary.Count)" -ForegroundColor White
Write-Host "  Applications used:          $($appSummary.Count)" -ForegroundColor White

Write-Host "`nScript complete!" -ForegroundColor Green

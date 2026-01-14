# Azure AD Outbound Tenant Access Analyzer

Find external Azure AD tenants that **your users have authenticated TO** (outbound cross-tenant access).

## Overview

These tools help you discover which external organizations your users are accessing. This is useful for:

- Security auditing
- Compliance reviews
- Understanding B2B collaboration patterns
- Identifying shadow IT

### Key Concepts

| Field | Description |
|-------|-------------|
| `HomeTenantId` | Your tenant (where your users live) |
| `ResourceTenantId` | The external tenant being accessed |

When `HomeTenantId != ResourceTenantId`, your users are accessing an external organization.

## Quick Start

### Option 1: Bash Script (Recommended for Azure Gov)

```bash
# Make executable
chmod +x run-query.sh

# Interactive mode
./run-query.sh

# Run specific query
./run-query.sh 1   # Summary of external tenants
./run-query.sh 2   # Detailed access logs
./run-query.sh 3   # By user
./run-query.sh 4   # By application
```

### Option 2: Log Analytics / Sentinel

Copy queries from `find_outbound_tenant_access.kql` into your Log Analytics workspace.

**Quick query:**

```kql
SigninLogs
| where TimeGenerated > ago(30d)
| where HomeTenantId != ResourceTenantId
| where isnotempty(ResourceTenantId)
| summarize AccessCount = count(), UniqueUsers = dcount(UserPrincipalName)
    by ResourceTenantId
| order by AccessCount desc
```

### Option 3: PowerShell (Microsoft Graph)

```powershell
# Install prerequisites
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Reports -Scope CurrentUser

# Run the script
.\Get-OutboundTenantAccess.ps1 -Days 30
.\Get-OutboundTenantAccess.ps1 -Days 7 -ExportPath "C:\Reports\Outbound.csv"
```

## Files

| File | Description |
|------|-------------|
| `run-query.sh` | Interactive bash script for running queries (Azure Gov compatible) |
| `find_outbound_tenant_access.kql` | 12 KQL queries for Log Analytics/Sentinel |
| `Get-OutboundTenantAccess.ps1` | PowerShell script using Microsoft Graph API |
| `Lookup-TenantName.ps1` | Resolve tenant GUIDs to tenant info |

## Available Queries

1. **Summary** - External tenants your users accessed
2. **Detailed** - Recent outbound access logs with full details
3. **By User** - Which users access external tenants
4. **By App** - Which applications access external tenants
5. **Failed** - Failed external access attempts
6. **Timeline** - When external tenants were first accessed
7. **Consent Analysis** - Cross-tenant app consents
8. **Non-Interactive** - Service account/automation access
9. **Trends** - Daily access patterns
10. **Comprehensive** - Combined interactive + non-interactive
11. **Footprint** - Quick summary statistics
12. **Resources** - What resources in external tenants

## Looking Up Tenant Names

Once you have tenant IDs, identify them:

```powershell
.\Lookup-TenantName.ps1 -TenantId "d555ab3f-c29b-49cc-a7d4-f69a66e1d017"
```

Or manually:
```
https://login.microsoftonline.com/{tenant-id}/.well-known/openid-configuration
```

## Prerequisites

### For Bash Script
- Azure CLI (`az`) logged in
- `az rest` command available

### For PowerShell
- Microsoft.Graph.Authentication module
- Microsoft.Graph.Reports module
- Permissions: `AuditLog.Read.All`, `Directory.Read.All`

### For KQL Queries
- Azure AD sign-in logs sent to Log Analytics workspace
- Reader access to the workspace

## Security Considerations

Review outbound access for:
- Unexpected tenant IDs (users accessing unknown organizations)
- High-volume access to external tenants
- Access outside business relationships
- Sensitive users with external access (admins, executives)

To control outbound access:
> Microsoft Entra ID > External Identities > Cross-tenant access settings > Outbound access settings

## License

MIT

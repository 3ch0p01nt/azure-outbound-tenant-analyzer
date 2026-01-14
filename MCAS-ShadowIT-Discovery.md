# Shadow IT Discovery with Microsoft Defender for Cloud Apps (MCAS)

Since you have E5 licensing, MCAS provides much better Shadow IT discovery than sign-in logs alone.

## Why MCAS is Better

| Method | What it catches |
|--------|-----------------|
| SigninLogs (this repo) | Only apps using "Sign in with Microsoft" |
| MCAS Cloud Discovery | ALL cloud apps - regardless of auth method |

## Quick Start - MCAS Portal

1. Go to: **https://security.microsoft.com** (or https://portal.cloudappsecurity.us for Gov)
2. Navigate to: **Cloud Apps > Cloud Discovery**
3. View the **Discovered Apps** dashboard

## Setting Up Cloud Discovery

### Option 1: Microsoft Defender for Endpoint Integration (Recommended)

If you have MDE deployed, it automatically feeds traffic data to MCAS:

1. Go to **Settings > Cloud Apps > Microsoft Defender for Endpoint**
2. Enable the integration
3. MDE agents will report cloud app traffic automatically

### Option 2: Firewall/Proxy Log Upload

Upload logs from your network devices:

1. **Cloud Apps > Cloud Discovery > Create snapshot report**
2. Upload logs from: Palo Alto, Cisco, Zscaler, etc.
3. MCAS parses and categorizes the apps

### Option 3: Continuous Reports

For ongoing monitoring:

1. **Cloud Apps > Cloud Discovery > Continuous reports**
2. Configure automatic log upload from your firewall/proxy

## Key Reports in MCAS

### Discovered Apps Dashboard
- Total apps discovered
- Risk levels (High/Medium/Low)
- Categories (Storage, Collaboration, AI, etc.)

### App Risk Scores
Each app gets a score based on:
- Security controls
- Compliance certifications
- Legal terms
- General reputation

### Shadow IT by User
See which users are accessing which unsanctioned apps.

## Governance Actions

Once you find Shadow IT, you can:

1. **Sanction** - Mark as approved
2. **Unsanction** - Mark as blocked (integrates with Defender for Endpoint to block)
3. **Monitor** - Track usage
4. **Tag** - Custom categorization

## KQL Queries for MCAS Data in Sentinel

If MCAS data is flowing to Sentinel:

```kql
// Discovered cloud apps
McasShadowItReporting
| where TimeGenerated > ago(30d)
| summarize
    TotalTraffic = sum(BytesUploaded) + sum(BytesDownloaded),
    UniqueUsers = dcount(UserName)
    by AppName, AppCategory
| order by TotalTraffic desc

// High-risk app usage
McasShadowItReporting
| where TimeGenerated > ago(30d)
| where AppScore < 5  // Apps with low trust scores
| summarize
    Users = make_set(UserName, 20),
    UniqueUsers = dcount(UserName),
    TotalEvents = count()
    by AppName, AppScore
| order by UniqueUsers desc

// AI/ML apps (common Shadow IT)
McasShadowItReporting
| where TimeGenerated > ago(30d)
| where AppCategory == "Generative AI" or AppName contains "AI" or AppName contains "GPT"
| summarize
    Users = make_set(UserName, 20),
    UniqueUsers = dcount(UserName)
    by AppName
| order by UniqueUsers desc
```

## MCAS API for Automation

```powershell
# Get discovered apps via API
$token = Get-MgAccessToken -Scopes "https://api.cloudappsecurity.com/.default"

$headers = @{
    "Authorization" = "Bearer $token"
}

# List discovered apps
$apps = Invoke-RestMethod -Uri "https://portal.cloudappsecurity.us/api/v1/discovery/discovered_apps/" -Headers $headers -Method Get

$apps.data | Sort-Object -Property traffic -Descending | Select-Object -First 20
```

## Gov Cloud URLs

- Portal: https://portal.cloudappsecurity.us
- API: https://portal.cloudappsecurity.us/api/

## Combining Both Approaches

For complete Shadow IT visibility:

1. **MCAS Cloud Discovery** - Catches ALL cloud app traffic
2. **SigninLogs (this repo)** - Shows which apps got Azure AD consent/access

Together they give you:
- What apps are being used (MCAS)
- Which have corporate credential access (SigninLogs)
- User attribution for both

#!/bin/bash
# Run KQL queries against Azure Log Analytics (Government Cloud)
# Usage: ./run-query.sh [query-number]

WORKSPACE_ID="0c6547ef-e3f7-4b5f-a211-813ce162c7c2"
API_URL="https://api.loganalytics.us/v1/workspaces/${WORKSPACE_ID}/query"

# Define queries
declare -A QUERIES

QUERIES[1]='SigninLogs | where TimeGenerated > ago(30d) | where HomeTenantId != ResourceTenantId | where isnotempty(ResourceTenantId) | summarize AccessCount = count(), UniqueUsers = dcount(UserPrincipalName), Apps = make_set(AppDisplayName, 10) by ResourceTenantId | order by AccessCount desc'

QUERIES[2]='SigninLogs | where TimeGenerated > ago(30d) | where HomeTenantId != ResourceTenantId | where isnotempty(ResourceTenantId) | project TimeGenerated, UserPrincipalName, UserDisplayName, HomeTenantId, ResourceTenantId, AppDisplayName, ResourceDisplayName, IPAddress, ResultType | order by TimeGenerated desc | take 50'

QUERIES[3]='SigninLogs | where TimeGenerated > ago(30d) | where HomeTenantId != ResourceTenantId | where isnotempty(ResourceTenantId) | summarize ExternalTenantCount = dcount(ResourceTenantId), TotalSignIns = count() by UserPrincipalName | where ExternalTenantCount > 0 | order by ExternalTenantCount desc'

QUERIES[4]='SigninLogs | where TimeGenerated > ago(30d) | where HomeTenantId != ResourceTenantId | where isnotempty(ResourceTenantId) | summarize SignInCount = count(), UniqueUsers = dcount(UserPrincipalName), ExternalTenants = make_set(ResourceTenantId, 10) by AppDisplayName | order by SignInCount desc'

QUERIES[5]='SigninLogs | where TimeGenerated > ago(30d) | where HomeTenantId != ResourceTenantId | where isnotempty(ResourceTenantId) | where ResultType != 0 | summarize FailedAttempts = count(), ErrorCodes = make_set(ResultType, 10) by ResourceTenantId, AppDisplayName | order by FailedAttempts desc'

QUERIES[6]='SigninLogs | where TimeGenerated > ago(90d) | where HomeTenantId != ResourceTenantId | where isnotempty(ResourceTenantId) | summarize FirstAccess = min(TimeGenerated), LastAccess = max(TimeGenerated), TotalAccesses = count(), UniqueUsers = dcount(UserPrincipalName) by ResourceTenantId | order by FirstAccess asc'

show_menu() {
    echo "=================================="
    echo "OUTBOUND TENANT ACCESS QUERIES"
    echo "=================================="
    echo ""
    echo "1. Summary: External tenants your users accessed"
    echo "2. Detailed: Recent outbound access logs"
    echo "3. By User: Which users access external tenants"
    echo "4. By App: Which apps access external tenants"
    echo "5. Failed: Failed external access attempts"
    echo "6. Timeline: When external tenants were first accessed"
    echo ""
    echo "c. Custom query (enter your own KQL)"
    echo "q. Quit"
    echo ""
}

run_query() {
    local query="$1"
    echo '{"query": "'"${query}"'"}' > /tmp/kql_query.json

    echo "Running query..."
    echo ""

    result=$(az rest --method post --url "$API_URL" --body @/tmp/kql_query.json 2>&1)

    if echo "$result" | grep -q '"error"'; then
        echo "ERROR: Query failed"
        echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"
    else
        echo "$result" | python3 -c "
import json
import sys

data = json.load(sys.stdin)
if 'tables' in data and len(data['tables']) > 0:
    table = data['tables'][0]
    cols = [c['name'] for c in table['columns']]
    rows = table['rows']

    if not rows:
        print('No results found.')
    else:
        # Print header
        print(' | '.join(cols))
        print('-' * (sum(len(c) for c in cols) + 3 * len(cols)))

        # Print rows
        for row in rows:
            print(' | '.join(str(v) if v is not None else '' for v in row))

        print()
        print(f'Total rows: {len(rows)}')
else:
    print('No data returned')
" 2>/dev/null || echo "$result" | python3 -m json.tool
    fi

    rm -f /tmp/kql_query.json
}

# Check if az is logged in
if ! az account show &>/dev/null; then
    echo "Error: Not logged into Azure. Run 'az login' first."
    exit 1
fi

# If argument provided, run that query directly
if [ -n "$1" ]; then
    if [ "$1" = "c" ] || [ "$1" = "custom" ]; then
        echo "Enter your KQL query (single line):"
        read -r custom_query
        run_query "$custom_query"
    elif [ -n "${QUERIES[$1]}" ]; then
        run_query "${QUERIES[$1]}"
    else
        echo "Invalid query number. Use 1-6 or 'c' for custom."
        exit 1
    fi
    exit 0
fi

# Interactive mode
while true; do
    show_menu
    read -p "Select query (1-6, c, or q): " choice
    echo ""

    case $choice in
        1|2|3|4|5|6)
            run_query "${QUERIES[$choice]}"
            ;;
        c)
            echo "Enter your KQL query (single line):"
            read -r custom_query
            run_query "$custom_query"
            ;;
        q)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid choice. Please select 1-6, c, or q."
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
    echo ""
done

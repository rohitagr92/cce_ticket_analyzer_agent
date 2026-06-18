<#
.SYNOPSIS
    Sets up the Azure Table for ticket statistics and generates REST API access information

.DESCRIPTION
    This script:
    1. Deletes the existing TicketCategoryStats table if it exists
    2. Creates a new TicketCategoryStats table with updated schema
    3. Generates a SAS token for REST API access
    4. Outputs sample REST API queries

    New Schema (one row per incident):
    - PartitionKey: YearWeek (e.g., "2026-W06")
    - RowKey: IncidentID (e.g., "INC15285226")
    - Category: The assigned category
    - Date: Incident date (YYYY-MM-DD)
    - YearWeek: Year and week string (YYYY-Wnn)

.EXAMPLE
    .\Setup-StatisticsTable.ps1
    
.EXAMPLE
    .\Setup-StatisticsTable.ps1 -ForceRecreate
#>

param(
    [string]$StorageAccountName = "opswprodtoolsblob",
    [string]$ResourceGroupName = "OPSW-Ticket-Analyzer",
    [string]$TableName = "IncidentsCategoryStats",
    [int]$SasExpiryDays = 365,
    [switch]$ForceRecreate
)

Write-Host "=== Azure Table Storage Setup for Incident Statistics ===" -ForegroundColor Cyan
Write-Host ""

# Check if logged in to Azure
$azContext = Get-AzContext
if (-not $azContext) {
    Write-Host "Not logged in to Azure. Please log in..." -ForegroundColor Yellow
    Connect-AzAccount
}

Write-Host "Using Azure subscription: $($azContext.Subscription.Name)" -ForegroundColor Green
Write-Host ""

# Get storage account key
Write-Host "Getting storage account key..." -ForegroundColor Cyan
$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
$storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageKey

# Check if table exists
Write-Host "Checking for existing table: $TableName..." -ForegroundColor Cyan
$existingTable = Get-AzStorageTable -Name $TableName -Context $storageContext -ErrorAction SilentlyContinue

if ($existingTable) {
    Write-Host "Table '$TableName' already exists." -ForegroundColor Yellow
    
    if ($ForceRecreate) {
        Write-Host "ForceRecreate specified - deleting existing table..." -ForegroundColor Yellow
        Remove-AzStorageTable -Name $TableName -Context $storageContext -Force
        Write-Host "Table deleted. Waiting 30 seconds for Azure to complete deletion..." -ForegroundColor Yellow
        Start-Sleep -Seconds 30
    } else {
        $confirm = Read-Host "Do you want to delete and recreate the table with new schema? (y/n)"
        if ($confirm -eq 'y' -or $confirm -eq 'Y') {
            Write-Host "Deleting existing table..." -ForegroundColor Yellow
            Remove-AzStorageTable -Name $TableName -Context $storageContext -Force
            Write-Host "Table deleted. Waiting 30 seconds for Azure to complete deletion..." -ForegroundColor Yellow
            Start-Sleep -Seconds 30
        } else {
            Write-Host "Keeping existing table. Exiting..." -ForegroundColor Yellow
            exit 0
        }
    }
}

# Create new table
Write-Host "Creating table: $TableName..." -ForegroundColor Cyan
$retryCount = 0
$maxRetries = 5

while ($retryCount -lt $maxRetries) {
    try {
        $table = New-AzStorageTable -Name $TableName -Context $storageContext -ErrorAction Stop
        Write-Host "Table created: $TableName" -ForegroundColor Green
        break
    } catch {
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Write-Host "Table creation failed (may still be deleting). Waiting 15 seconds... (Attempt $retryCount/$maxRetries)" -ForegroundColor Yellow
            Start-Sleep -Seconds 15
        } else {
            Write-Host "Failed to create table after $maxRetries attempts: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
}

# Generate SAS token for table access
Write-Host ""
Write-Host "Generating SAS token (valid for $SasExpiryDays days)..." -ForegroundColor Cyan

$sasExpiry = (Get-Date).AddDays($SasExpiryDays)
$sasToken = New-AzStorageTableSASToken -Name $TableName -Context $storageContext -Permission raud -ExpiryTime $sasExpiry

Write-Host "SAS token generated" -ForegroundColor Green

# Output REST API information
$baseUrl = "https://$StorageAccountName.table.core.windows.net/$TableName"

Write-Host ""
Write-Host "=== REST API Access Information ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Base URL:" -ForegroundColor Yellow
Write-Host "  $baseUrl"
Write-Host ""
Write-Host "SAS Token (valid until $($sasExpiry.ToString('yyyy-MM-dd'))):" -ForegroundColor Yellow
Write-Host "  $sasToken"
Write-Host ""
Write-Host "Full URL with SAS:" -ForegroundColor Yellow
Write-Host "  $baseUrl$sasToken"
Write-Host ""

Write-Host "=== NEW Table Schema (One Row Per Incident) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host @"
Each record contains:
  - PartitionKey: YearWeek string (e.g., "2026-W06") - for efficient weekly queries
  - RowKey: Incident ID (e.g., "INC15285226") - unique identifier
  - Category: Assigned category name
  - Date: Incident date (YYYY-MM-DD)
  - YearWeek: Year and week string (YYYY-Wnn)
  - Year: Year number
  - WeekNumber: ISO week number
  - Timestamp: Auto-generated by Azure
"@ -ForegroundColor Gray

Write-Host ""
Write-Host "=== Sample REST API Queries ===" -ForegroundColor Cyan
Write-Host ""

$currentWeek = "{0:D4}-W{1:D2}" -f (Get-Date).Year, [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear((Get-Date), [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday)

$queries = @{
    "Get all incidents" = "${baseUrl}$sasToken"
    "Get incidents for current week ($currentWeek)" = "${baseUrl}?`$filter=PartitionKey%20eq%20'$currentWeek'$sasToken"
    "Get incidents for specific week (e.g., 2026-W05)" = "${baseUrl}?`$filter=PartitionKey%20eq%20'2026-W05'$sasToken"
    "Get incidents by category" = "${baseUrl}?`$filter=Category%20eq%20'Hardware%20Issues'$sasToken"
    "Get incidents for specific date" = "${baseUrl}?`$filter=Date%20eq%20'$((Get-Date).ToString('yyyy-MM-dd'))'$sasToken"
    "Get specific incident by ID" = "${baseUrl}(PartitionKey='$currentWeek',RowKey='INC15285226')$sasToken"
    "Count incidents per category (client-side aggregation needed)" = "${baseUrl}?`$select=Category$sasToken"
}

foreach ($query in $queries.GetEnumerator()) {
    Write-Host "$($query.Key):" -ForegroundColor Yellow
    Write-Host "  $($query.Value)" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "=== Usage Examples ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "PowerShell - Get all incidents for a week:" -ForegroundColor Yellow
Write-Host @"
    `$response = Invoke-RestMethod -Uri "${baseUrl}?`$filter=PartitionKey%20eq%20'$currentWeek'$sasToken" -Headers @{Accept='application/json'}
  `$response.value | Format-Table RowKey, Category, Date
"@ -ForegroundColor Gray

Write-Host ""
Write-Host "PowerShell - Count by category:" -ForegroundColor Yellow
Write-Host @"
    `$response = Invoke-RestMethod -Uri "${baseUrl}$sasToken" -Headers @{Accept='application/json'}
  `$response.value | Group-Object Category | Select-Object Name, Count | Sort-Object Count -Descending
"@ -ForegroundColor Gray

Write-Host ""
Write-Host "JavaScript/Fetch:" -ForegroundColor Yellow
Write-Host @"
    const url = "${baseUrl}?`$filter=PartitionKey eq '$currentWeek'$sasToken";
  fetch(url, { headers: { 'Accept': 'application/json' } })
    .then(r => r.json())
    .then(data => {
      // Group by category
      const byCategory = data.value.reduce((acc, inc) => {
        acc[inc.Category] = (acc[inc.Category] || 0) + 1;
        return acc;
      }, {});
      console.log(byCategory);
    });
"@ -ForegroundColor Gray

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""

# Save configuration to a file for reference
$configOutput = @{
    StorageAccount = $StorageAccountName
    TableName = $TableName
    BaseUrl = $baseUrl
    SasToken = $sasToken
    SasExpiry = $sasExpiry.ToString('yyyy-MM-dd')
    FullUrl = "$baseUrl$sasToken"
    Schema = @{
        PartitionKey = "YearWeek (e.g., 2026-W06)"
        RowKey = "IncidentID (e.g., INC15285226)"
        Properties = @("Category", "Date", "YearWeek", "Year", "WeekNumber")
    }
}

$configPath = ".\statistics-api-config.json"
$configOutput | ConvertTo-Json -Depth 3 | Set-Content -Path $configPath
Write-Host "Configuration saved to: $configPath" -ForegroundColor Green

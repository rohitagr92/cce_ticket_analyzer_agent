# Daily Structure Implementation - Azure Automation Updates

## Current Situation

Your WW26 workflow was successful:
1. ✅ Load incidents (audit CSV + ServiceNow)
2. ✅ Apply strict template corrections
3. ✅ Add Confidence levels (High/Low)
4. ✅ Regenerate dashboard

**To automate this daily, update these Azure runbooks:**

---

## 1. incident-analyzer-rb-prodtools.ps1 (MAIN - Already Partially Ready)

**Current State:** ✅ Already handles Confidence levels
- Extracts `confidence_level` from AI response
- Normalizes to "High" / "Medium" / "Low"
- Stores in table as `Confidence` field

**What's Missing:** ❌ Dashboard regeneration
- After writing to IncidentsCategoryStats table, doesn't call Build-WeeklyReports.ps1

**Update Needed:** Add dashboard generation call
```powershell
# At the end of the main analyzer runbook, add:

# ---- Regenerate dashboard for current week ----
Write-Output "Regenerating weekly report..."
try {
    $reportScriptPath = "setup/reporting/Build-WeeklyReports.ps1"
    & $reportScriptPath -OnlyWeeks $currentYearWeek
    Write-Output "Dashboard regenerated successfully"
} catch {
    Write-Warning "Failed to regenerate dashboard: $_"
}
```

---

## 2. incident-trend-backfill-rb-prodtools.ps1 (Daily Backfill)

**Current State:** ✅ Analyzes new incidents daily
- Queries ServiceNow for last 2 days
- Categorizes with AI
- Writes to IncidentsCategoryStats table
- Adds Confidence field

**What's Missing:** ❌ Dashboard regeneration
- After backfill completes, doesn't trigger report generation

**Update Needed:** Add dashboard call
```powershell
# At the end of the backfill, add:

# ---- Regenerate dashboards for affected weeks ----
Write-Output "Regenerating weekly reports for backfilled weeks..."
try {
    $affectedWeeks = @()  # Collect unique YearWeeks from backfilled incidents
    foreach ($week in $affectedWeeks | Select-Object -Unique) {
        & "setup/reporting/Build-WeeklyReports.ps1" -OnlyWeeks $week
    }
    Write-Output "Reports regenerated successfully"
} catch {
    Write-Warning "Failed to regenerate reports: $_"
}
```

---

## 3. Option A: Keep as-is + Manual Regeneration (Simplest)

**No code changes needed:**
- Runbooks analyze and categorize incidents daily ✅
- Data stored with Confidence levels ✅
- Manually regenerate dashboard when needed:
  ```powershell
  .\setup\reporting\Build-WeeklyReports.ps1  # Regenerate all weeks
  ```

**Pros:** Simple, low risk, straightforward  
**Cons:** Manual step required

---

## 4. Option B: Auto-Regenerate Daily (Recommended)

**Add a new runbook:** `dashboard-regenerator-rb.ps1`

This runs **after** the analyzer completes:

```powershell
<#
.SYNOPSIS
    Regenerate all weekly reports from IncidentsCategoryStats table.
    Scheduled to run daily after incident-analyzer-rb-prodtools.

.DESCRIPTION
    Calls Build-WeeklyReports.ps1 to regenerate all weekly dashboard HTML
    reports with latest incident categorization and Confidence levels.
#>

param(
    [string]$OnlyWeeks  # Optional: specific weeks to regenerate
)

# [Setup: same as other runbooks - load config, connect to Azure]
# Connect-AzAccount -Identity
# Set-AzContext -Subscription $SubscriptionId

# Call Build-WeeklyReports.ps1
$reportScript = "setup/reporting/Build-WeeklyReports.ps1"

if ($OnlyWeeks) {
    & $reportScript -OnlyWeeks $OnlyWeeks.Split(',')
} else {
    & $reportScript  # Regenerate all weeks
}

Write-Output "Dashboard regeneration complete"
```

**Schedule in Automation Account:**
- Runbook: `dashboard-regenerator-rb`
- Schedule: Daily 7:00 UTC (after analyzer at 6:30 UTC)
- Parameters: (none - regenerates all weeks)

---

## 5. Daily Workflow (After Updates)

```
6:00 AM UTC
  ↓
incident-analyzer-rb-prodtools
  • Fetch today's incidents from ServiceNow
  • AI categorization → IncidentsCategoryStats
  • Add Confidence (High/Low/Medium)
  ↓
6:30 AM UTC
  ↓
incident-trend-backfill-rb-prodtools
  • Backfill last 2 days of missed incidents
  • Same AI categorization + Confidence
  ↓
7:00 AM UTC
  ↓
dashboard-regenerator-rb (NEW)
  • Read all weeks from IncidentsCategoryStats
  • Build HTML reports
  • Upload to Blob storage
  ↓
7:15 AM UTC
  ↓
User opens dashboard → sees latest data with High/Low Confidence
```

---

## 6. Implementation Checklist

### Option A (Manual Regeneration)
- [ ] No code changes (runbooks already handle Confidence)
- [ ] Document manual regeneration command
- [ ] User runs: `.\setup\reporting\Build-WeeklyReports.ps1` when needed

### Option B (Auto Regeneration - Recommended)
- [ ] Create `runbooks/dashboard-regenerator-rb.ps1`
- [ ] Update `incident-analyzer-rb-prodtools.ps1` to call `Build-WeeklyReports.ps1`
- [ ] Update `incident-trend-backfill-rb-prodtools.ps1` to call `Build-WeeklyReports.ps1`
- [ ] Create schedule in Azure Automation Account
- [ ] Test: Run analyzer + regenerator + verify dashboard updates
- [ ] Monitor: Check logs for dashboard build failures

---

## 7. Key Points

**All runbooks already support:**
- ✅ Strict template categorization
- ✅ Confidence levels (High/Low/Medium)
- ✅ IncidentsCategoryStats table writes

**What needs to be added:**
- ❌ Dashboard regeneration call in automation
- ❌ Scheduled dashboard regenerator runbook

**After implementation, every day will:**
1. Analyze new incidents → Confidence field
2. Regenerate dashboard → Shows High/Low confidence distribution
3. All automatic - no manual steps

---

## Commands Reference

**Regenerate dashboard for all weeks:**
```powershell
.\setup\reporting\Build-WeeklyReports.ps1
```

**Regenerate specific weeks:**
```powershell
.\setup\reporting\Build-WeeklyReports.ps1 -OnlyWeeks '2026-W26','2026-W27'
```

**Check last analyzer run logs** (Azure Portal):
- Automation Account → Runbooks → incident-analyzer-rb-prodtools → All Logs

**Check confidence field in table:**
```powershell
$rows = Get-AzTableRow -Table $table.CloudTable -PartitionKey "2026-W26"
$rows | Group-Object Confidence | Select-Object Name, Count
# Output:
# Name  Count
# ----  -----
# High     34
# Low       8
```

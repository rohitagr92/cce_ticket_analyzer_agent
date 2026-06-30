# Dashboard Structure & Update Process

## Overview

The Productivity Tools dashboard is a collection of HTML reports automatically generated from incident data stored in Azure Table Storage (`IncidentsCategoryStats`). Each weekly report provides interactive filtering, categorization breakdown, and root cause analysis.

---

## Architecture

### Data Flow

```
IncidentsCategoryStats Table (Azure)
    ↓ (grouped by YearWeek partition)
Build-WeeklyReports.ps1
    ↓ (generates HTML with filtering)
Blob Storage: results/ProductivityTools_Weekly_Report_<YYYY>-W<NN>.html
    ↓ (user reads via Static Web App + SAS token)
User Browser Dashboard
```

### Storage Locations

| Component | Location | Purpose |
|-----------|----------|---------|
| **Table** | `IncidentsCategoryStats` | Incident records with full taxonomy |
| **Blob Container** | `results/` | Weekly HTML reports |
| **Frontend** | Static Web App: `opsw-prodtools-reports` | Interactive dashboard UI |

---

## Data Requirements

### Table Schema: IncidentsCategoryStats

**Partitioning:** `PartitionKey = YearWeek` (e.g., `"2026-W26"`)

**Required Fields per Incident (RowKey = IncidentNumber):**

| Field | Type | Purpose | Example |
|-------|------|---------|---------|
| `PartitionKey` | string | Year-week identifier | `"2026-W26"` |
| `RowKey` | string | Incident number (unique) | `"INC15557930"` |
| `Category` | string | Product category from canonical catalog | `"Microsoft OneDrive Issues"` |
| `Subcategory` | string | Symptom/sub-issue per category | `"Sync Issues"` |
| `TopRootCause` | string | Root cause label from canonical list | `"Rejoin Access Issue"` |
| `DetailedRootCause` | string | Expanded root cause explanation | `"Rejoined user account missing legacy permissions"` |
| `AIAnalysis` | string | Detailed AI-generated analysis (100+ chars) | `"User lost access to shared OneDrive/SharePoint item following account rejoin..."` |
| `Date` | string (ISO 8601) | Incident resolved/closed date | `"2026-06-24T14:23:00Z"` |
| `State` | string | Incident state | `"Resolved"` or `"Closed"` |
| `YearWeek` | string | Denormalized partition key | `"2026-W26"` |
| `Year` | int | Calendar year for filtering | `2026` |
| `WeekNumber` | int | ISO week number | `26` |

### Validation Requirements

Every record **MUST** satisfy:

1. **Category Validity**
   - Must match one of these from `TicketCategorisation_ProductivityTools.md`:
     - Microsoft OneDrive Issues
     - Microsoft 365 Apps for Enterprise Issues
     - Microsoft 365 Copilot Issues
     - Microsoft Excel Issues
     - Microsoft PowerPoint Issues
     - Microsoft OneNote Issues
     - Microsoft Forms Issues
     - Microsoft Project Issues
     - Shared File Service (Share Drives) Issues
     - Rejoin / Account Lifecycle Access Issues
     - Windows OS Issues
     - Hardware Issues
     - ... (or "Unknown" if insufficient data)

2. **Subcategory Validity**
   - Must match the parent category's valid list from `TrendSubCategorisation_ProductivityTools.md`
   - Examples:
     - OneDrive → ["Sync Issues", "Access & Permission Issues", "PC Refresh Issues", ...]
     - Copilot → ["Licensing Issues", "Feature Availability Issues", "Usage Queries", ...]

3. **RootCause Validity**
   - Must match exactly one entry from `PossibleRootCause_ProductivityTools.md` for the selected category
   - Examples:
     - OneDrive: "Sync Stall", "Rejoin Access Issue", "Sign-In / Connectivity Failure", ...
     - Copilot: "Copilot License Blackout", "Copilot SKU Not Provisioned", ...
     - Fallback for truly unknown: "Insufficient Documentation"

4. **AIAnalysis Quality**
   - Minimum length: 100 characters
   - Must contain actionable information (no placeholders like "pending", "to be analyzed", etc.)
   - Must explain the issue and suggest remediation
   - No "Unknown" markers unless incident is genuinely out-of-scope

---

## Dashboard Report Structure

### File Format

**Naming Convention:**  
`ProductivityTools_Weekly_Report_<YYYY>-W<NN>.html`

**Example:**  
`ProductivityTools_Weekly_Report_2026-W26.html`

### Report Sections

#### 1. Header
- Week identifier (e.g., "WW26")
- Date range (Sunday → Saturday, IST)
- Generation timestamp

#### 2. KPI Cards (Summary Statistics)
```
┌─────────────────────────────────────────────┐
│ Total Incidents │ Resolved │ Closed │ ... │
│      42         │   30     │   12   │     │
└─────────────────────────────────────────────┘
```

Cards include:
- **Total incidents** - sum of all rows in week
- **Resolved (State=6)** - incident state
- **Closed (State=7)** - incident state
- **Distinct products** - count of unique Categories
- **Top product + count** - most frequent Category

#### 3. Product Breakdown Section
Interactive table: **Issues sorted by Product**
- Columns: Product | Count | Share % | Incident numbers
- Rows per Category, sorted by frequency
- Clickable incident numbers that filter detail table

#### 4. Root Cause Breakdown Section
Interactive table: **Issues sorted by Possible Root Cause**
- Columns: Root Cause | Count | Share % | Incident numbers
- Rows per TopRootCause, sorted by frequency
- Clickable incident numbers that filter detail table

#### 5. Detailed Incident Table
Full incident list with:
- **Incident** - clickable link to ServiceNow
- **Resolved at** - Date field
- **Category (Product)** - color-coded by category
- **Subcategory (Symptom)** - observable issue type
- **Possible Root Cause** - TopRootCause field
- **Detailed Root Cause** - DetailedRootCause field
- **AI Analysis** - AIAnalysis field (searchable, scrollable)

#### 6. Interactive Features
- **Filter by group**: Click a row in Product/RootCause breakdown → filters detail table
- **Jump to incident**: Click incident number → filters to that group + highlights row with smooth scroll
- **Clear filter**: Button to reset all filters
- **Live count**: Detail section title shows filtered count

---

## Update Workflow

### When to Regenerate Dashboard

Dashboard should be regenerated whenever:

1. **New incidents are added** to a week partition
2. **Incident data is corrected** (Category, RootCause, AIAnalysis)
3. **Taxonomy changes** (new valid categories or root causes)

### Manual Regeneration (Ad-Hoc)

**Regenerate single week:**
```powershell
cd <repo-root>
.\setup\reporting\Build-WeeklyReports.ps1 -OnlyWeeks '2026-W26'
```

**Regenerate multiple weeks:**
```powershell
.\setup\reporting\Build-WeeklyReports.ps1 -OnlyWeeks '2026-W25','2026-W26','2026-W27'
```

**Regenerate all weeks:**
```powershell
.\setup\reporting\Build-WeeklyReports.ps1
```

### Automated Regeneration (Scheduled)

The `incident-trend-backfill-rb-prodtools` runbook in Azure Automation:
- Runs daily (after `incident-analyzer-rb-prodtools`)
- Automatically calls `Build-WeeklyReports.ps1` for all weeks
- No manual intervention needed

---

## Color Scheme

Product categories are assigned consistent colors for visual consistency:

| Category | Color | Hex |
|----------|-------|-----|
| Hardware Issues | Red | #e74c3c |
| Drivers and BIOS Issues | Orange | #e67e22 |
| Windows OS Issues | Blue | #3498db |
| Network / Connectivity Issues | Teal | #1abc9c |
| Browser Issues | Pink | #e91e63 |
| Microsoft 365 Apps | Dark Blue | #0078d4 |
| Microsoft OneDrive | Navy | #005a9e |
| Microsoft Copilot | Purple | #464feb |
| Microsoft Excel | Green | #107c41 |
| Excluded | Gray | #90a4ae |

(Complete list in `setup\reporting\Build-WeeklyReports.ps1` under `$CategoryColors`)

---

## Future Consistency Requirements

### Template Compliance Checklist

For each future week's dashboard:

- [ ] All 42+ incidents have a Category from the canonical list
- [ ] All incidents have a Subcategory matching their Category's valid list
- [ ] All incidents have a TopRootCause from the canonical list for their Category
- [ ] All AIAnalysis fields contain 100+ characters of meaningful narrative
- [ ] Zero "Unknown" markers unless genuinely out-of-scope
- [ ] Date fields are populated (ISO 8601 format)
- [ ] State field is "Resolved" or "Closed"
- [ ] Dashboard HTML renders without errors
- [ ] Filtering works correctly (click group → filters detail table)
- [ ] Incident links point to correct ServiceNow records

### Taxonomy Updates

When adding new categories, subcategories, or root causes:

1. **Update templates** in `templates/` directory:
   - `TicketCategorisation_ProductivityTools.md`
   - `TrendSubCategorisation_ProductivityTools.md`
   - `PossibleRootCause_ProductivityTools.md`

2. **Update colors** in `setup\reporting\Build-WeeklyReports.ps1`:
   - Add entry to `$CategoryColors` hashtable

3. **Regenerate all dashboards**:
   ```powershell
   .\setup\reporting\Build-WeeklyReports.ps1
   ```

4. **Validate** with compliance script:
   ```powershell
   .\tools\verify_ww26_compliance.ps1  # (or update for desired week)
   ```

---

## Troubleshooting

### Dashboard shows "0 incidents"
- **Cause**: Week partition not in table
- **Fix**: Verify incidents were inserted with correct PartitionKey (YearWeek format)

### Filtering not working
- **Cause**: Data-* attributes missing or malformed
- **Fix**: Verify Category, Subcategory, TopRootCause fields are populated and HTML-safe

### Report doesn't upload to blob
- **Cause**: Storage account access permissions or content-type mismatch
- **Fix**: Verify script runs with correct Azure context and `ContentType='text/html'` is set

### Links point to wrong incidents
- **Cause**: RowKey format mismatch
- **Fix**: Ensure incident numbers match ServiceNow format (e.g., `INC15557930`)

---

## Example: Complete WW26 Dashboard Update

**Scenario**: Just corrected all 42 WW26 incidents with detailed AI analysis.

**Steps:**

1. **Verify data in table**:
   ```powershell
   $table = Get-AzStorageTable -Name IncidentsCategoryStats -Context $ctx
   $rows = Get-AzTableRow -Table $table.CloudTable -PartitionKey "2026-W26"
   Write-Host "Found $($rows.Count) incidents"
   ```

2. **Regenerate dashboard**:
   ```powershell
   .\setup\reporting\Build-WeeklyReports.ps1 -OnlyWeeks '2026-W26'
   ```

3. **Expected output**:
   ```
   Connecting to storage...
   Loaded 621 incident rows from table.
   Uploaded ProductivityTools_Weekly_Report_2026-W26.html (42 incidents)
   Done. Reload the Reports tab to see the new weekly reports.
   ```

4. **Verify in dashboard**:
   - Open Static Web App dashboard
   - Navigate to "Reports+" tab
   - Select WW26 from dropdown
   - Verify all 42 incidents appear with correct Category colors
   - Test filtering by clicking a product category
   - Confirm incident links work

---

## References

- Architecture: [docs/ARCHITECTURE.md](ARCHITECTURE.md)
- Incident analyzer runbook: `runbooks/incident-analyzer-rb-prodtools.ps1`
- Trend backfill runbook: `runbooks/incident-trend-backfill-rb-prodtools.ps1`
- Report builder: `setup/reporting/Build-WeeklyReports.ps1`
- Templates: `templates/TicketCategorisation_*.md`, `TrendSubCategorisation_*.md`, `PossibleRootCause_*.md`

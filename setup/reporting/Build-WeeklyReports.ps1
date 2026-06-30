<#
.SYNOPSIS
    Generates per-week HTML report blobs from the IncidentsCategoryStats table data and
    uploads them to the 'results' container. Companion to Backfill-TrendData.ps1.

.DESCRIPTION
    Reads all rows from IncidentsCategoryStats, groups by YearWeek, and for each week
    renders a self-contained HTML page with:
      - KPI cards (total, in-scope vs excluded, top category)
      - Category breakdown table
      - Per-incident list (Number, Date, Category)
    Uploads each report as ProductivityTools_Weekly_Report_<YYYY>-W<NN>.html (overwriting).

.PARAMETER OnlyWeeks
    Optional: array of YearWeek strings (e.g. '2026-W20','2026-W21') to (re)generate.
    Default: all weeks present in the table.

.EXAMPLE
  .\setup\reporting\Build-WeeklyReports.ps1
.EXAMPLE
  .\setup\reporting\Build-WeeklyReports.ps1 -OnlyWeeks '2026-W20','2026-W21'
#>

[CmdletBinding()]
param(
    [string[]]$OnlyWeeks,
    [string]$ResourceGroup = 'OPSW-Ticket-Analyzer',
    [string]$StorageAccount = 'opswprodtoolsblob',
    [string]$TableName = 'IncidentsCategoryStats',
    [string]$ContainerName = 'results'
)

$ErrorActionPreference = 'Stop'

function HtmlEsc { param([string]$s) if ($null -eq $s) { return '' } [System.Net.WebUtility]::HtmlEncode($s) }

# Category color palette (matches web/index.html)
$CategoryColors = @{
    'Hardware Issues'                          = '#e74c3c'
    'Drivers and BIOS Issues'                  = '#e67e22'
    'How Do I / User Education'                = '#f39c12'
    'Compliance/Policy Issues'                 = '#2ecc71'
    'Windows OS Issues'                        = '#3498db'
    'Network / Connectivity Issues'            = '#1abc9c'
    'Slowness / Performance Issues'            = '#9b59b6'
    'Browser Issues'                           = '#e91e63'
    'Application Issues'                       = '#00bcd4'
    'Microsoft 365 Apps for Enterprise Issues' = '#0078d4'
    'Microsoft OneDrive Issues'                = '#005a9e'
    'Microsoft OneNote Issues'                 = '#7719aa'
    'Microsoft Excel Issues'                   = '#107c41'
    'Microsoft 365 Copilot Issues'             = '#464feb'
    'Microsoft Forms Issues'                   = '#6264a7'
    'Microsoft Project Issues'                 = '#ba141a'
    'Shared File Service (Share Drives) Issues' = '#ff9800'
    'Rejoin / Account Lifecycle Access Issues' = '#8bc34a'
    'Excluded'                                 = '#90a4ae'
}
function ColorFor { param([string]$c) if ($CategoryColors.ContainsKey($c)) { $CategoryColors[$c] } else { '#5b6abf' } }

# -------- Read all table rows --------
Write-Host "Connecting to storage..." -ForegroundColor Cyan
$key = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $key

$sas = New-AzStorageTableSASToken -Name $TableName -Permission 'r' -ExpiryTime (Get-Date).AddMinutes(15) -Protocol HttpsOnly -Context $ctx
$base = "https://$StorageAccount.table.core.windows.net/$TableName()?$sas"
$rows = @()
$url = $base
while ($url) {
  $resp = Invoke-WebRequest -Uri $url -Headers @{ Accept = 'application/json;odata=nometadata' } -UseBasicParsing
  $raw = $resp.Content
  if ($raw -match '"SubCategory"' -and $raw -match '"Subcategory"') {
    $raw = $raw -replace '"SubCategory"','"SubCategory_legacy"'
  }
  $json = $raw | ConvertFrom-Json
  if ($json.value) {
    foreach ($it in $json.value) {
      if ($it.PSObject.Properties.Name -contains 'SubCategory_legacy') {
        $val = $it.SubCategory_legacy
        $it | Add-Member -NotePropertyName 'Subcategory' -NotePropertyValue $val -Force
      } elseif ($it.PSObject.Properties.Name -contains 'SubCategory') {
        $val = $it.SubCategory
        $it | Add-Member -NotePropertyName 'Subcategory' -NotePropertyValue $val -Force
      }
      $rows += $it
    }
  }
  $npk = $resp.Headers['x-ms-continuation-NextPartitionKey']
  $nrk = $resp.Headers['x-ms-continuation-NextRowKey']
    if ($npk) {
        $url = $base + '&NextPartitionKey=' + [Uri]::EscapeDataString([string]$npk)
        if ($nrk) { $url += '&NextRowKey=' + [Uri]::EscapeDataString([string]$nrk) }
    }
    else { $url = $null }
}
Write-Host "Loaded $($rows.Count) incident rows from table." -ForegroundColor Green

# -------- Build HTML for each week --------
$weeks = $rows | Group-Object PartitionKey | Sort-Object Name
if ($OnlyWeeks) { $weeks = $weeks | Where-Object { $OnlyWeeks -contains $_.Name } }

foreach ($wkGroup in $weeks) {
    $yearWeek = $wkGroup.Name
    $incidents = @($wkGroup.Group) | Sort-Object Date -Descending
    $total = $incidents.Count
    $excluded = ($incidents | Where-Object { $_.Category -eq 'Excluded' }).Count
    $inScope = $total - $excluded

    $byCategory = $incidents | Group-Object Category | Sort-Object Count -Descending
    $topCat = if ($byCategory.Count -gt 0) { $byCategory[0] } else { $null }

    # ---- IST Sun-Sat date range from YearWeek (US/Intel convention) ----
    $dateRange = ''
    $istStart = $null; $istEnd = $null
    if ($yearWeek -match '^(?<y>\d{4})-W(?<w>\d{1,2})$') {
        $yyy = [int]$Matches.y; $wkn = [int]$Matches.w
        $jan1 = (Get-Date -Year $yyy -Month 1 -Day 1).Date
        $week1Sun = $jan1.AddDays(-1 * [int]$jan1.DayOfWeek)
        $istStart = $week1Sun.AddDays(($wkn - 1) * 7)
        $istEnd   = $istStart.AddDays(6)
        $dateRange = "$($istStart.ToString('ddd dd MMM yyyy')) -> $($istEnd.ToString('ddd dd MMM yyyy')) (IST)"
    }

    # Resolved vs Closed split (from State column, fallback unknown)
    $stResolved = ($incidents | Where-Object { $_.State -eq 'Resolved' }).Count
    $stClosed   = ($incidents | Where-Object { $_.State -eq 'Closed'   }).Count
    if ($stResolved + $stClosed -eq 0) { $stResolved = $total; $stClosed = 0 }  # legacy rows without State

    # ----- Three sorted views: by Product, by Symptom, by Possible Root Cause -----
    # Each section lists, per group, the incident numbers as clickable anchors that
    # (a) jump to the detail row and (b) filter the detail table to that group.
    function BuildBreakdown {
        param([string]$Property, [string]$Heading, [string]$FilterKey)
        $groups = $incidents | Group-Object $Property | Where-Object { $_.Name } | Sort-Object Count -Descending
        if ($groups.Count -eq 0) { return '' }
        $rowsHtml = ($groups | ForEach-Object {
                $grpName = $_.Name
                $grpCount = $_.Count
                $pct = if ($total -gt 0) { [math]::Round(($grpCount / $total) * 100, 1) } else { 0 }
                $color = ColorFor $grpName
                $grpAttr = [System.Net.WebUtility]::HtmlEncode($grpName) -replace "'", '&#39;'
                $incLinks = ($_.Group | Sort-Object Date -Descending | ForEach-Object {
                        $n = HtmlEsc $_.RowKey
                        "<a href='#inc-$n' class='inc-link' data-inc='$n' data-filter-key='$FilterKey' data-filter-value=`"$grpAttr`">$n</a>"
                    }) -join ', '
                @"
<tr class='grp-row' data-filter-key='$FilterKey' data-filter-value="$grpAttr">
  <td><span class='dot' style='background:$color'></span><strong>$(HtmlEsc $grpName)</strong></td>
  <td class='num'>$grpCount</td>
  <td class='num'>$pct%</td>
  <td class='inc-cell'>$incLinks</td>
</tr>
"@
            }) -join "`n"
        @"
  <div class="section">
    <h2>$Heading <span class='filter-hint' id='hint-$FilterKey'></span></h2>
    <table class='breakdown-table'>
      <thead><tr><th>$Heading</th><th class="num">Count</th><th class="num">Share</th><th>Incident numbers (click to filter / jump)</th></tr></thead>
      <tbody>
$rowsHtml
      </tbody>
    </table>
  </div>
"@
    }

    $byProductHtml   = BuildBreakdown -Property 'Category'     -Heading 'Issues sorted by Product'         -FilterKey 'product'
    $byRootCauseHtml = BuildBreakdown -Property 'TopRootCause' -Heading 'Issues sorted by Possible Root Cause' -FilterKey 'rootcause'

    $byCategory = $incidents | Group-Object Category | Sort-Object Count -Descending
    $topCat = if ($byCategory.Count -gt 0) { $byCategory[0] } else { $null }
    $topCatName = if ($topCat) { HtmlEsc $topCat.Name } else { '-' }
    $topCatCount = if ($topCat) { $topCat.Count } else { 0 }

    # Per-incident detailed table - 7 columns - each row carries data-* for filtering and id="inc-<num>" for anchor jump.
    $incRows = ($incidents | Sort-Object Date -Descending | ForEach-Object {
            $color = ColorFor $_.Category
            $num   = HtmlEsc $_.RowKey
            $cat   = HtmlEsc $_.Category
            $sub   = HtmlEsc $_.Subcategory
            $top   = HtmlEsc $_.TopRootCause
            $det   = HtmlEsc $_.DetailedRootCause
            $anal  = HtmlEsc $_.AIAnalysis
            $date  = HtmlEsc $_.Date
            $catAttr = $cat -replace "'", '&#39;'
            $subAttr = $sub -replace "'", '&#39;'
            $topAttr = $top -replace "'", '&#39;'
            $url   = "https://intel.service-now.com/nav_to.do?uri=incident.do?sysparm_query=number=$num"
            "<tr id='inc-$num' class='detail-row' data-product=`"$catAttr`" data-symptom=`"$subAttr`" data-rootcause=`"$topAttr`"><td><a href='$url' target='_blank' rel='noopener'>$num</a></td><td>$date</td><td><span class='dot' style='background:$color'></span>$cat</td><td>$sub</td><td>$top</td><td>$det</td><td>$anal</td></tr>"
        }) -join "`n"

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<title>Productivity Tools - Detailed Incident Analysis $yearWeek</title>
<style>
:root { --intel-classic:#003C71; --intel-blue:#0071C5; --bg:#f4f7fb; --card:#fff; --text:#1a2433; --muted:#5b6b7f; --border:#dde4ee; }
* { box-sizing:border-box; }
body { margin:0; font-family:'Segoe UI',Tahoma,sans-serif; background:var(--bg); color:var(--text); }
header { background:linear-gradient(135deg, var(--intel-classic), var(--intel-blue)); color:#fff; padding:28px 32px; }
header h1 { margin:0 0 6px 0; font-size:1.7rem; font-weight:600; }
header .sub { color:rgba(255,255,255,0.92); font-size:1rem; }
header .sub strong { color:#fff; }
main { max-width:1500px; margin:0 auto; padding:24px 32px; }
.stats { display:grid; grid-template-columns:repeat(auto-fit,minmax(170px,1fr)); gap:14px; margin-bottom:24px; }
.stat-card { background:var(--card); border:1px solid var(--border); border-radius:10px; padding:16px 18px; }
.stat-card .num { font-size:1.8rem; font-weight:700; color:var(--intel-classic); }
.stat-card .label { color:var(--muted); font-size:0.85rem; margin-top:2px; }
.section { background:var(--card); border:1px solid var(--border); border-radius:10px; padding:20px 22px; margin-bottom:20px; }
.section h2 { margin:0 0 14px 0; font-size:1.1rem; color:var(--intel-classic); }
table { width:100%; border-collapse:collapse; font-size:0.9rem; }
th, td { text-align:left; padding:9px 10px; border-bottom:1px solid var(--border); vertical-align:top; }
th { background:#eef5fb; color:var(--intel-classic); font-weight:600; }
td.num { text-align:right; font-variant-numeric:tabular-nums; }
.dot { display:inline-block; width:10px; height:10px; border-radius:50%; margin-right:6px; vertical-align:middle; }
a { color:var(--intel-blue); text-decoration:none; }
a:hover { text-decoration:underline; }
footer { text-align:center; color:var(--muted); font-size:0.8rem; padding:20px; }
.detail-table td { max-width:320px; word-wrap:break-word; }
.inc-cell { font-size:0.82rem; line-height:1.55; }
.inc-link { display:inline-block; padding:1px 4px; margin:1px 1px; background:#eef5fb; border:1px solid #d3e3f1; border-radius:3px; font-variant-numeric:tabular-nums; }
.inc-link:hover { background:#0071C5; color:#fff !important; text-decoration:none; }
.grp-row { cursor:pointer; }
.grp-row:hover td { background:#f0f7ff; }
.grp-row.active td { background:#fff3cd; }
.detail-row.flash td { background:#fff3cd !important; transition:background 1.6s; }
.detail-row.hidden { display:none; }
.filter-hint { font-size:0.75rem; color:var(--muted); font-weight:400; margin-left:8px; }
.clear-filter { display:inline-block; margin-left:10px; padding:3px 9px; background:var(--intel-blue); color:#fff; border-radius:4px; font-size:0.75rem; cursor:pointer; }
.clear-filter:hover { background:var(--intel-classic); }
</style>
</head>
<body>
<header>
  <h1>Productivity Tools - Detailed Incident Analysis $yearWeek</h1>
  <div class="sub"><strong>From:</strong> $($istStart.ToString('dddd, dd MMM yyyy')) &nbsp; <strong>To:</strong> $($istEnd.ToString('dddd, dd MMM yyyy')) &nbsp; (IST, Sun -> Sat)</div>
  <div class="sub" style="margin-top:4px;">State filter: Resolved + Closed &middot; Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') IST</div>
</header>
<main>
  <div class="stats">
    <div class="stat-card"><div class="num">$total</div><div class="label">Total incidents</div></div>
    <div class="stat-card"><div class="num">$stResolved</div><div class="label">Resolved (state 6)</div></div>
    <div class="stat-card"><div class="num">$stClosed</div><div class="label">Closed (state 7)</div></div>
    <div class="stat-card"><div class="num">$($byCategory.Count)</div><div class="label">Distinct products</div></div>
    <div class="stat-card"><div class="num">$topCatCount</div><div class="label">Top: $topCatName</div></div>
  </div>

$byProductHtml

$byRootCauseHtml

  <div class="section" id="detail-section">
    <h2>Detailed incident analysis <span id="detail-count">($total)</span> <span id="active-filter" class="filter-hint"></span> <span id="clear-filter-btn" class="clear-filter" style="display:none;">Clear filter</span></h2>
    <table class="detail-table">
      <thead><tr><th>Incident</th><th>Resolved at</th><th>Category (Product)</th><th>Subcategory (Symptom)</th><th>Possible Root Cause</th><th>Detailed Root Cause</th><th>AI Analysis</th></tr></thead>
      <tbody id="detail-tbody">
$incRows
      </tbody>
    </table>
  </div>
</main>
<footer>Intel End-User Collaboration &middot; Productivity Tools weekly report</footer>
<script>
(function () {
  var total = $total;
  var detailRows = document.querySelectorAll('.detail-row');
  var countEl = document.getElementById('detail-count');
  var filterEl = document.getElementById('active-filter');
  var clearBtn = document.getElementById('clear-filter-btn');
  var dataAttr = { product: 'data-product', symptom: 'data-symptom', rootcause: 'data-rootcause' };
  var keyLabel = { product: 'Product', symptom: 'Symptom', rootcause: 'Possible Root Cause' };

  function applyFilter(key, value) {
    var shown = 0;
    detailRows.forEach(function (r) {
      var match = (r.getAttribute(dataAttr[key]) === value);
      r.classList.toggle('hidden', !match);
      if (match) shown++;
    });
    countEl.textContent = '(' + shown + ' of ' + total + ')';
    filterEl.textContent = '- filtered by ' + keyLabel[key] + ': "' + value + '"';
    clearBtn.style.display = 'inline-block';
    document.querySelectorAll('.grp-row.active').forEach(function (g) { g.classList.remove('active'); });
    document.querySelectorAll('.grp-row[data-filter-key="' + key + '"][data-filter-value="' + value.replace(/"/g, '\\"') + '"]').forEach(function (g) { g.classList.add('active'); });
  }

  function clearFilter() {
    detailRows.forEach(function (r) { r.classList.remove('hidden'); });
    countEl.textContent = '(' + total + ')';
    filterEl.textContent = '';
    clearBtn.style.display = 'none';
    document.querySelectorAll('.grp-row.active').forEach(function (g) { g.classList.remove('active'); });
  }

  function flash(id) {
    var row = document.getElementById(id);
    if (!row) return;
    if (row.classList.contains('hidden')) row.classList.remove('hidden');
    row.classList.add('flash');
    row.scrollIntoView({ behavior: 'smooth', block: 'center' });
    setTimeout(function () { row.classList.remove('flash'); }, 1800);
  }

  // Click on a group row -> filter
  document.querySelectorAll('.grp-row').forEach(function (g) {
    g.addEventListener('click', function (e) {
      if (e.target.classList && e.target.classList.contains('inc-link')) return;
      var k = g.getAttribute('data-filter-key');
      var v = g.getAttribute('data-filter-value');
      applyFilter(k, v);
      document.getElementById('detail-section').scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  });

  // Click on an incident link -> filter to its group AND jump+flash
  document.querySelectorAll('.inc-link').forEach(function (a) {
    a.addEventListener('click', function (e) {
      e.preventDefault();
      var k = a.getAttribute('data-filter-key');
      var v = a.getAttribute('data-filter-value');
      var inc = a.getAttribute('data-inc');
      applyFilter(k, v);
      setTimeout(function () { flash('inc-' + inc); }, 80);
    });
  });

  clearBtn.addEventListener('click', clearFilter);
})();
</script>
</body>
</html>
"@

    $blobName = "ProductivityTools_Weekly_Report_$yearWeek.html"
    $tmp = Join-Path $env:TEMP $blobName
    Set-Content -Path $tmp -Value $html -Encoding UTF8

    Set-AzStorageBlobContent -File $tmp -Container $ContainerName -Blob $blobName -Context $ctx -Properties @{ ContentType = 'text/html; charset=utf-8' } -Force | Out-Null
    Remove-Item $tmp -Force

    Write-Host ("  Uploaded {0,-50} ({1} incidents)" -f $blobName, $total) -ForegroundColor Green
}

Write-Host "`nDone. Reload the Reports tab to see the new weekly reports." -ForegroundColor Cyan

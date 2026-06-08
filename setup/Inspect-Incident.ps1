param([string]$Incident = 'INC15539428')

$ErrorActionPreference = 'Stop'
$ctx = New-AzStorageContext -StorageAccountName 'opswprodtoolsblob' -UseConnectedAccount
$tbl = (Get-AzStorageTable -Name 'IncidentsCategoryStats' -Context $ctx).CloudTable
$rows = Get-AzTableRow -Table $tbl -CustomFilter ("RowKey eq '{0}'" -f $Incident)
Write-Host "RowCount=$($rows.Count)"
foreach ($r in $rows) {
    $aiLen = 0
    $aiHead = ''
    if ($r.AIAnalysis) { $aiLen = $r.AIAnalysis.Length; $aiHead = $r.AIAnalysis.Substring(0, [Math]::Min(160, $aiLen)) }
    [pscustomobject]@{
        PartitionKey      = $r.PartitionKey
        RowKey            = $r.RowKey
        Category          = $r.Category
        Subcategory       = $r.Subcategory
        RootCause         = $r.RootCause
        PossibleRootCause = $r.PossibleRootCause
        DetailedRootCause = $r.DetailedRootCause
        Confidence        = $r.Confidence
        AIAnalysisLen     = $aiLen
        AIAnalysisHead    = $aiHead
    } | Format-List
}

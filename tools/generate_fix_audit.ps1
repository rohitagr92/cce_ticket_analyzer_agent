param(
    [string[]]$YearWeeks = @('2026-W25','2026-W26'),
    [string]$ResourceGroup = 'OPSW-Ticket-Analyzer',
    [string]$StorageAccount = 'opswprodtoolsblob',
    [string]$TableName = 'IncidentsCategoryStats',
    [string]$OutCsv = ".\local-output\fix_audit_$(($YearWeeks -join '_')).csv"
)

Import-Module Az.Storage -ErrorAction Stop

function Normalize-TemplateText { param([string]$Raw) if ([string]::IsNullOrWhiteSpace($Raw)) { return '' } $text = $Raw -replace '[\u2010-\u2015]', '-' -replace '\*+', '' -replace '^[\["\s]+|["\]\s]+$','' -replace '\s+',' '; return $text.Trim() }

function Resolve-TemplateProductKey { param($Map,$Product) if (-not $Map -or [string]::IsNullOrWhiteSpace($Product)) { return $null } if ($Map.ContainsKey($Product)) { return $Product } foreach ($key in $Map.Keys) { if ($key -ieq $Product) { return $key } if ($Product -like "*${key}*" -or $key -like "*${Product}*") { return $key } } $stopWords = @('issues','microsoft','365','for','enterprise','the','and','of','a','an'); $tokenize = { param([string]$Value) $trimmed = ($Value -replace '\s*Issues\s*$','').ToLowerInvariant(); @([regex]::Split($trimmed, '[^a-z0-9]+') | Where-Object { $_ -and $_ -notin $stopWords }) }; $productTokens = & $tokenize $Product; if ($productTokens.Count -eq 0) { return $null } $bestKey = $null; $bestScore = 0; foreach ($key in $Map.Keys) { $keyTokens = & $tokenize $key; if ($keyTokens.Count -eq 0) { continue } $shared = @($productTokens | Where-Object { $keyTokens -contains $_ }).Count; if ($shared -gt $bestScore) { $bestScore = $shared; $bestKey = $key } } return $bestKey }

function Get-StrictSubcategoryRules {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $templatePath = Join-Path $repoRoot 'templates\TrendSubCategorisation_ProductivityTools.md'
    $rules = @{ Allowlists = @{}; AliasMap = @{}; AliasesByProduct = @{} }
    if (-not (Test-Path $templatePath)) { return $rules }
    $templateText = Get-Content $templatePath -Raw -Encoding UTF8
    $sections = [regex]::Split($templateText, '(?m)^####\s+') | Where-Object { $_ -match '\S' }
    foreach ($section in $sections) {
        $lines = $section -split "`r?`n", 2
        if ($lines.Count -lt 2) { continue }
        $product = $lines[0].Trim()
        $body = $lines[1]
        $headers = New-Object System.Collections.Generic.List[string]
        $aliases = @{}
        $currentHeader = ''
        foreach ($line in ($body -split "`r?`n")) {
            $trimmed = ([string]$line).Trim()
            if (-not $trimmed) { continue }
            if ($trimmed -match '^\*\*(.+?)\*\*\s*$') { $currentHeader = $matches[1].Trim(); if ($currentHeader -and -not $headers.Contains($currentHeader)) { [void]$headers.Add($currentHeader) }; continue }
            if ($trimmed -match '^\s*[-*]\s+(.+?)\s*$') { $symptom = ($matches[1].Trim() -replace '\s*\(.+?\)\s*$', ''); if ($currentHeader -and $symptom) { $symptomKey = Normalize-TemplateText -Raw $symptom; $productAliasKey = ('{0}||{1}' -f (Normalize-TemplateText -Raw $product), $symptomKey); $rules.AliasMap[$productAliasKey] = $currentHeader; $aliases[$symptomKey] = $currentHeader } }
        }
        if ($headers.Count -gt 0) { $rules.Allowlists[$product] = $headers; $rules.AliasesByProduct[$product] = $aliases }
    }
    return $rules
}

function Convert-ToStrictSubcategoryHeading { param($ParentCategory,$RawSubCategory,$ContextText='') $rules = Get-StrictSubcategoryRules; $productKey = Resolve-TemplateProductKey -Map $rules.Allowlists -Product $ParentCategory; if (-not $productKey) { return $RawSubCategory } $allowlist = $rules.Allowlists[$productKey]; if (-not $allowlist -or $allowlist.Count -eq 0) { return $RawSubCategory } $rawKey = Normalize-TemplateText -Raw $RawSubCategory; $aliasKey = ('{0}||{1}' -f (Normalize-TemplateText -Raw $productKey), $rawKey); if ($rawKey -and $rules.AliasMap.ContainsKey($aliasKey)) { return [string]$rules.AliasMap[$aliasKey] } foreach ($label in $allowlist) { $labelKey = Normalize-TemplateText -Raw $label; if ($label -ieq $RawSubCategory -or $labelKey -eq $rawKey) { return $label } if ($rawKey -and ($rawKey -like "*$labelKey*" -or $labelKey -like "*$rawKey*")) { return $label } } $searchText = Normalize-TemplateText -Raw ((@($RawSubCategory, $ContextText) -join ' ').Trim()); if ($searchText -and $rules.AliasesByProduct.ContainsKey($productKey)) { foreach ($symptomKey in $rules.AliasesByProduct[$productKey].Keys) { if ($searchText -like "*$symptomKey*") { return [string]$rules.AliasesByProduct[$productKey][$symptomKey] } } } return $allowlist[0] }

function Get-TableSas { param($ResourceGroup,$StorageAccount,$TableName) $key = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount)[0].Value; $ctx = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $key; $sas = New-AzStorageTableSASToken -Name $TableName -Permission raud -ExpiryTime (Get-Date).AddMinutes(30) -Context $ctx; return "https://$StorageAccount.table.core.windows.net/$TableName()$sas" }

function Get-EntitiesForPartition { param($TableBaseUrl,$PartitionKey) $filter = "`$filter=PartitionKey eq '$PartitionKey'"; $url = $TableBaseUrl + '&' + $filter + "&`$top=1000"; $all = @(); while ($url) {
        try {
            $r = Invoke-WebRequest -Uri $url -Headers @{ Accept = 'application/json;odata=nometadata' } -UseBasicParsing -TimeoutSec 60
        } catch {
            Write-Warning ("Table request failed for {0}: {1}" -f $PartitionKey, $_.Exception.Message)
            break
        }
        $raw = $r.Content
        if ($raw -match '"SubCategory"' -and $raw -match '"Subcategory"') { $raw = $raw -replace '"SubCategory"','"SubCategory_legacy"' }
        if (-not $raw) { break }
        $json = $raw | ConvertFrom-Json
        if ($json -and $json.value) {
            foreach ($item in $json.value) {
                if ($item.PSObject.Properties.Name -contains 'SubCategory_legacy') { $val = $item.SubCategory_legacy; $item | Add-Member -NotePropertyName 'SubCategory' -NotePropertyValue $val -Force }
                $all += $item
            }
        }
        $npk = $r.Headers['x-ms-continuation-NextPartitionKey']; $nrk = $r.Headers['x-ms-continuation-NextRowKey']
        if ($npk) {
            $nextPart = ''
            if ($nrk) { $nextPart = '&NextRowKey=' + [Uri]::EscapeDataString([string]$nrk) }
            $url = $TableBaseUrl + '&' + $filter + '&NextPartitionKey=' + [Uri]::EscapeDataString([string]$npk) + $nextPart
        } else { $url = $null }
    }
}

$sas = Get-TableSas -ResourceGroup $ResourceGroup -StorageAccount $StorageAccount -TableName $TableName
$tableBase = $sas

$rows = @()
foreach ($yw in $YearWeeks) {
    Write-Host "Scanning partition: $yw"
    $entities = Get-EntitiesForPartition -TableBaseUrl $tableBase -PartitionKey $yw
    foreach ($e in $entities) {
        $rowKey = $e.RowKey
        $current = ''
        if ($e.PSObject.Properties.Name -contains 'Subcategory' -and $e.Subcategory) { $current = [string]$e.Subcategory }
        elseif ($e.PSObject.Properties.Name -contains 'SubCategory' -and $e.SubCategory) { $current = [string]$e.SubCategory }
        $legacy = ''
        if ($e.PSObject.Properties.Name -contains 'SubCategory' -and $e.SubCategory) { $legacy = [string]$e.SubCategory }
        $contextText = [string]($e.DetailedRootCause) + ' ' + [string]($e.AIAnalysis)
        $mapped = Convert-ToStrictSubcategoryHeading -ParentCategory $e.Category -RawSubCategory ($legacy -or $current) -ContextText $contextText
        $rows += [PSCustomObject]@{ Partition = $yw; RowKey = $rowKey; CurrentSubcategory = $current; LegacySubCategory = $legacy; MappedSubcategory = $mapped }
    }
}

$diff = $rows | Where-Object { ($_.CurrentSubcategory -ne $_.MappedSubcategory) -or ($_.LegacySubCategory -and $_.LegacySubCategory -ne $_.MappedSubcategory) }
if (-not (Test-Path (Split-Path $OutCsv -Parent))) { New-Item -ItemType Directory -Path (Split-Path $OutCsv -Parent) -Force | Out-Null }
$diff | Select-Object Partition,RowKey,CurrentSubcategory,LegacySubCategory,MappedSubcategory | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8
Write-Host "Wrote audit CSV: $OutCsv (rows: $($diff.Count))"

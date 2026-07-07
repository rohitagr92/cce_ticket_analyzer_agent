$ErrorActionPreference = 'Stop'
$out = Join-Path $env:TEMP 'ce-bloblog.txt'
if (Test-Path $out) { Remove-Item $out -Force }
function Log { param($m) $m | Out-File -FilePath $out -Append -Encoding UTF8 }

$rg = 'OPSW-Ticket-Analyzer'; $sa = 'opswcontentenggblob'
$key = (Get-AzStorageAccountKey -ResourceGroupName $rg -Name $sa)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $sa -StorageAccountKey $key

Log "=== Recent blobs in 'logs' container ==="
$blobs = Get-AzStorageBlob -Container 'logs' -Context $ctx | Sort-Object LastModified -Descending | Select-Object -First 10
foreach ($b in $blobs) { Log ("  {0}  {1}  {2} bytes" -f $b.LastModified.UtcDateTime, $b.Name, $b.Length) }

$latest = $blobs | Select-Object -First 1
Log "`n=== Content of latest log: $($latest.Name) ==="
$tmp = Join-Path $env:TEMP ('celog_' + [guid]::NewGuid().ToString('N') + '.txt')
Get-AzStorageBlobContent -Container 'logs' -Blob $latest.Name -Destination $tmp -Context $ctx -Force | Out-Null
$lines = Get-Content $tmp
Log "TOTAL LINES: $($lines.Count)"
Log "`n--- Lines containing error/fail/exception/token/categoriz/fallback ---"
$lines | Select-String -Pattern 'error|fail|exception|token|categoriz|fallback|401|403|429|500|timed|timeout|OpenAI|content filter|empty' | Select-Object -First 80 | ForEach-Object { Log $_.Line }
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
"DONE" | Out-File -FilePath $out -Append -Encoding UTF8
Write-Output "Written to $out"

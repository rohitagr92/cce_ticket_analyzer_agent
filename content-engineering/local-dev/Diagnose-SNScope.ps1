$config  = Import-PowerShellDataFile "$PSScriptRoot\..\config\LocalConfig-ContentEngineering.psd1"
$secrets = Import-PowerShellDataFile "$PSScriptRoot\..\config\LocalSecrets-ContentEngineering.psd1"
$tok = (Invoke-RestMethod -Uri $config.TokenUrl -Method Post -Body @{
    grant_type='client_credentials'; client_id=$config.ServiceNowClientID
    client_secret=$secrets.ServiceNowClientSecret; scope=$config.ServiceNowScope
} -ContentType 'application/x-www-form-urlencoded').access_token
$h    = @{ Authorization = "Bearer $tok" }
$base = "https://apis.intel.com/itsm/api/now/table/incident"
$flds = "number,short_description,state,business_service,service_offering,assignment_group,resolved_at"

function Fetch($q, $label) {
    $enc = [uri]::EscapeDataString($q)
    $r = Invoke-RestMethod -Uri "${base}?sysparm_query=${enc}&sysparm_display_value=true&sysparm_fields=${flds}&sysparm_limit=3" -Headers $h
    Write-Host "`n$label  ->  $($r.result.Count) result(s)" -ForegroundColor Cyan
    $r.result | ForEach-Object {
        Write-Host "  $($_.number) | state=$($_.state)"
        Write-Host "    bs='$($_.business_service)'  so='$($_.service_offering)'  ag='$($_.assignment_group)'"
    }
}

Write-Host "=== Content Engineering SN Diagnostic ===" -ForegroundColor Yellow

# 1. Fetch the reference incident by sys_id to reveal real BS/SO values
Write-Host "`nTest 1: Fetch reference incident sys_id=f81e6ce5c3f98b901d9832d605013164" -ForegroundColor Cyan
$ref = Invoke-RestMethod -Uri "${base}?sysparm_query=sys_id=f81e6ce5c3f98b901d9832d605013164&sysparm_display_value=true&sysparm_fields=number,short_description,state,business_service,service_offering,assignment_group,category,subcategory" -Headers $h
if ($ref.result.Count -gt 0) {
    $i = $ref.result[0]
    Write-Host "  Found: $($i.number) | state=$($i.state)" -ForegroundColor Green
    Write-Host "  Business Service : $($i.business_service)" -ForegroundColor Green
    Write-Host "  Service Offering : $($i.service_offering)" -ForegroundColor Green
    Write-Host "  Assignment Group : $($i.assignment_group)" -ForegroundColor Green
    Write-Host "  Category / Sub   : $($i.category) / $($i.subcategory)"
    Write-Host "  Description      : $($i.short_description)"
} else { Write-Host "  Not found (access issue or wrong sys_id)" -ForegroundColor Red }

# 2. DYNAMIC assignment_group from the URL (resolved tickets)
Fetch "assignment_groupDYNAMICd6435e965f510100a9ad2572f2b47744^stateIN6,7^ORDERBYDESCresolved_at" `
      "Test 2: assignment_groupDYNAMIC d6435e965f510100a9ad2572f2b47744 (resolved)"

# 3. Static assignment_group sys_id (resolved tickets)
Fetch "assignment_group=d6435e965f510100a9ad2572f2b47744^stateIN6,7^ORDERBYDESCresolved_at" `
      "Test 3: assignment_group=d6435e965f510100a9ad2572f2b47744 (resolved)"

# 4. Static assignment_group (open tickets - states 1/2/3 from the URL)
Fetch "assignment_group=d6435e965f510100a9ad2572f2b47744^stateIN1,2,3^ORDERBYDESCopened_at" `
      "Test 4: assignment_group=d6435e965f510100a9ad2572f2b47744 (open)"

Write-Host "`nDone." -ForegroundColor Green

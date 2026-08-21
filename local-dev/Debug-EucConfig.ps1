param([string]$ConfigPath = 'end-user-conferencing\config\LocalConfig-EndUserConferencing.psd1')

$abs = (Resolve-Path $ConfigPath).Path
$cfg = Import-PowerShellDataFile -Path $abs

Write-Host ("Type: " + $cfg.GetType().FullName)
Write-Host ("Keys: " + ($cfg.Keys -join ','))
Write-Host ("PSObj props: " + ($cfg.PSObject.Properties.Name -join ','))
Write-Host ("Contains via Keys: " + ($cfg.Keys -contains 'RoomsServiceOfferingId'))
Write-Host ("Contains via PSObject: " + ($cfg.PSObject.Properties.Name -contains 'RoomsServiceOfferingId'))
Write-Host ("RoomsServiceOfferingId = " + $cfg['RoomsServiceOfferingId'])
Write-Host ("BusinessServiceId = " + $cfg['BusinessServiceId'])
Write-Host ("TokenUrl = " + $cfg['TokenUrl'])
Write-Host ("ServiceNowClientID = " + $cfg['ServiceNowClientID'])

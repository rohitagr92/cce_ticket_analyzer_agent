[CmdletBinding()]
param()

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot '..\_shared\EucRunbookCore.ps1')

Invoke-EucRunbook -OfferingName 'Messaging - Teams Chat and Audio' -Mode 'TrendBackfill' -Notes 'Messaging backfill path for End User Conferencing.'

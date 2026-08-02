[CmdletBinding()]
param()

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot '..\_shared\EucRunbookCore.ps1')

Invoke-EucRunbook -OfferingName 'Meetings - Rooms and Hardware' -Mode 'TrendBackfill' -Notes 'Rooms backfill path for End User Conferencing.'

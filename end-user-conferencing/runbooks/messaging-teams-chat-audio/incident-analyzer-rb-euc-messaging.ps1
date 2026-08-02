[CmdletBinding()]
param()

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot '..\_shared\EucRunbookCore.ps1')

Invoke-EucRunbook -OfferingName 'Messaging - Teams Chat and Audio' -Mode 'Analyzer' -Notes 'Messaging analyzer path for End User Conferencing.'

<#
.SYNOPSIS
    Uploads Content Engineering prompt templates to Azure Blob Storage.

.DESCRIPTION
    Publishes only files from content-engineering/templates to the target
    templates container, replacing any existing blobs in that container.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = 'OPSW-Ticket-Analyzer',
    [string]$StorageAccountName = 'opswcontentenggblob',
    [string]$ContainerName = 'templates'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$templateDir = Join-Path $repoRoot 'content-engineering\templates'

if (-not (Test-Path $templateDir)) {
    throw "Template folder not found: $templateDir"
}

$templateFiles = Get-ChildItem -Path $templateDir -Filter '*.md' -File
if (-not $templateFiles) {
    throw "No .md template files found in: $templateDir"
}

Write-Host "Uploading Content Engineering templates..." -ForegroundColor Cyan
Write-Host "Storage account: $StorageAccountName" -ForegroundColor DarkGray
Write-Host "Container: $ContainerName" -ForegroundColor DarkGray

$null = Get-AzContext -ErrorAction Stop
$key = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $key

$container = Get-AzStorageContainer -Name $ContainerName -Context $ctx -ErrorAction SilentlyContinue
if (-not $container) {
    New-AzStorageContainer -Name $ContainerName -Context $ctx -Permission Off | Out-Null
}

# Keep the container CE-only by removing previous blobs first.
Get-AzStorageBlob -Container $ContainerName -Context $ctx -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-AzStorageBlob -Container $ContainerName -Blob $_.Name -Context $ctx -Force | Out-Null }

foreach ($file in $templateFiles) {
    Set-AzStorageBlobContent -File $file.FullName -Container $ContainerName -Blob $file.Name -Context $ctx -Force | Out-Null
    Write-Host "  Uploaded: $($file.Name)" -ForegroundColor DarkGray
}

Write-Host "Upload complete. Files now in '$ContainerName':" -ForegroundColor Green
Get-AzStorageBlob -Container $ContainerName -Context $ctx |
    Select-Object Name, @{n='LastModifiedUtc'; e={$_.LastModified.UtcDateTime}}, Length |
    Sort-Object Name |
    Format-Table -AutoSize

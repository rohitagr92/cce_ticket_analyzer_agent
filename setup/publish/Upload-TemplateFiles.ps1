# Upload Template Files to Azure Blob Storage
# This script uploads the prompt template markdown files to Azure Storage

param(
    [string]$StorageAccountName = "opswprodtoolsblob",
    [string]$ContainerName = "templates",
    [string]$ResourceGroupName = "OPSW-Ticket-Analyzer"
)

Write-Host "`n=== Uploading Template Files to Azure Blob Storage ===" -ForegroundColor Cyan
Write-Host "Storage Account: $StorageAccountName" -ForegroundColor Gray
Write-Host "Container: $ContainerName" -ForegroundColor Gray
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Gray
Write-Host ""

# Define the template files to upload
# Blob name (what runbook expects) = local file path
$templateFiles = @{
    "WorkNotesCleanup_ProductivityTools.md"       = "$PSScriptRoot\..\..\templates\WorkNotesCleanup_ProductivityTools.md"
    "WorkNotesSummary_ProductivityTools.md"       = "$PSScriptRoot\..\..\templates\WorkNotesSummary_ProductivityTools.md"
    "TicketCategorisation_ProductivityTools.md"   = "$PSScriptRoot\..\..\templates\TicketCategorisation_ProductivityTools.md"
    "TrendSubCategorisation_ProductivityTools.md" = "$PSScriptRoot\..\..\templates\TrendSubCategorisation_ProductivityTools.md"
    "EnvironmentContext_ProductivityTools.md"     = "$PSScriptRoot\..\..\templates\EnvironmentContext_ProductivityTools.md"
    "PossibleRootCause_ProductivityTools.md"      = "$PSScriptRoot\..\..\templates\PossibleRootCause_ProductivityTools.md"
    "DetailedRootCause_ProductivityTools.md"      = "$PSScriptRoot\..\..\templates\DetailedRootCause_ProductivityTools.md"
}

try {
    # Check Azure connection
    Write-Host "Checking Azure connection..." -ForegroundColor Yellow
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not connected to Azure. Please sign in..." -ForegroundColor Yellow
        Connect-AzAccount -UseDeviceAuthentication
    } else {
        Write-Host "Connected as: $($context.Account.Id)" -ForegroundColor Green
    }
    
    # Get storage context using the account key (works for users with Reader+Contributor but no Storage Blob Data Contributor role)
    Write-Host "`nCreating storage context via account key..." -ForegroundColor Yellow
    $saKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop)[0].Value
    $storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $saKey
    Write-Host "Storage context created" -ForegroundColor Green
    
    # Check if container exists, create if not
    Write-Host "`nChecking container existence..." -ForegroundColor Yellow
    $container = Get-AzStorageContainer -Name $ContainerName -Context $storageContext -ErrorAction SilentlyContinue
    
    if (-not $container) {
        Write-Host "Container '$ContainerName' not found. Creating..." -ForegroundColor Yellow
        New-AzStorageContainer -Name $ContainerName -Context $storageContext -Permission Off | Out-Null
        Write-Host "Container created" -ForegroundColor Green
    } else {
        Write-Host "Container exists" -ForegroundColor Green
    }
    
    # Remove all existing blobs from the container
    Write-Host "`n=== Removing Old Blobs from Container ===" -ForegroundColor Cyan
    $existingBlobs = Get-AzStorageBlob -Container $ContainerName -Context $storageContext -ErrorAction SilentlyContinue
    if ($existingBlobs) {
        foreach ($blob in $existingBlobs) {
            Remove-AzStorageBlob -Blob $blob.Name -Container $ContainerName -Context $storageContext -Force
            Write-Host "  Deleted: $($blob.Name)" -ForegroundColor DarkGray
        }
        Write-Host "Old blobs removed." -ForegroundColor Green
    } else {
        Write-Host "Container is already empty." -ForegroundColor Gray
    }

    # Upload each template file
    Write-Host "`n=== Uploading Template Files ===" -ForegroundColor Cyan
    $uploadedCount = 0
    $failedFiles = @()
    
    foreach ($blobName in $templateFiles.Keys) {
        $filePath = $templateFiles[$blobName]
        
        # Check if file exists
        if (-not (Test-Path $filePath)) {
            Write-Host "File not found: $filePath" -ForegroundColor Red
            $failedFiles += $blobName
            continue
        }
        
        try {
            Write-Host "Uploading: $blobName..." -ForegroundColor Yellow

            # Upload file to blob storage (without .md extension in blob name).
            # -ErrorAction Stop is critical — otherwise 403s only print to stderr and the script lies about success.
            Set-AzStorageBlobContent -File $filePath `
                                     -Container $ContainerName `
                                     -Blob $blobName `
                                     -Context $storageContext `
                                     -Force `
                                     -ErrorAction Stop | Out-Null

            # Get file size for display
            $fileSize = [math]::Round((Get-Item $filePath).Length / 1KB, 1)

            Write-Host "  Uploaded: $blobName ($fileSize KB)" -ForegroundColor Green
            $uploadedCount++

        } catch {
            Write-Host "  Failed to upload $blobName : $($_.Exception.Message)" -ForegroundColor Red
            $failedFiles += $blobName
        }
    }
    
    # Summary
    Write-Host "`n=== Upload Summary ===" -ForegroundColor Cyan
    Write-Host "Successfully uploaded: $uploadedCount/$($templateFiles.Count) files" -ForegroundColor $(if ($uploadedCount -eq $templateFiles.Count) { "Green" } else { "Yellow" })
    
    if ($failedFiles.Count -gt 0) {
        Write-Host "Failed files: $($failedFiles -join ', ')" -ForegroundColor Red
    }
    
    # List all blobs in container
    Write-Host "`n=== Files in Container ===" -ForegroundColor Cyan
    $blobs = Get-AzStorageBlob -Container $ContainerName -Context $storageContext
    
    if ($blobs) {
        foreach ($blob in $blobs) {
            $blobSize = [math]::Round($blob.Length / 1KB, 1)
            $lastModified = $blob.LastModified.ToString("yyyy-MM-dd HH:mm:ss")
            Write-Host "  $($blob.Name) ($blobSize KB, Modified: $lastModified)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  No files found in container" -ForegroundColor Yellow
    }
    
    Write-Host "`nTemplate upload process completed!" -ForegroundColor Green
    Write-Host "Your runbook can now access these templates from blob storage." -ForegroundColor Cyan
    
} catch {
    Write-Host "`nError during upload process:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Ensure you're connected to Azure: Connect-AzAccount" -ForegroundColor Gray
    Write-Host "2. Verify you have 'Storage Blob Data Contributor' role on the storage account" -ForegroundColor Gray
    Write-Host "3. Check that the storage account name is correct: $StorageAccountName" -ForegroundColor Gray
    Write-Host "4. Ensure the template files exist in the .\Templates\ directory" -ForegroundColor Gray
}

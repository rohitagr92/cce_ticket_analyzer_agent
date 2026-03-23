# Upload Template Files to Azure Blob Storage
# This script uploads the prompt template markdown files to Azure Storage

param(
    [string]$StorageAccountName = "incidentsanalyzersa",
    [string]$ContainerName = "templates",
    [string]$ResourceGroupName = "Incidents-analyzer-rg"
)

Write-Host "`n=== Uploading Template Files to Azure Blob Storage ===" -ForegroundColor Cyan
Write-Host "Storage Account: $StorageAccountName" -ForegroundColor Gray
Write-Host "Container: $ContainerName" -ForegroundColor Gray
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Gray
Write-Host ""

# Define the template files to upload (without .md extension for blob names)
$templateFiles = @{
    "WorkNotesCleanup.md" = "$PSScriptRoot\..\templates\WorkNotesCleanup.md"
    "WorkNotesSummary.md" = "$PSScriptRoot\..\templates\WorkNotesSummary.md"
    "TicketCategorisation.md" = "$PSScriptRoot\..\templates\TicketCategorisation.md"
    "EnvironmentContext.md" = "$PSScriptRoot\..\templates\EnvironmentContext.md"
    "TrendSubCategorisation.md" = "$PSScriptRoot\..\templates\TrendSubCategorisation.md"
}

try {
    # Check Azure connection
    Write-Host "Checking Azure connection..." -ForegroundColor Yellow
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not connected to Azure. Please sign in..." -ForegroundColor Yellow
        Connect-AzAccount -UseDeviceAuthentication
    } else {
        Write-Host "✓ Connected as: $($context.Account.Id)" -ForegroundColor Green
    }
    
    # Get storage account key
    Write-Host "`nGetting storage account key..." -ForegroundColor Yellow
    $storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
    
    # Create storage context using account key
    Write-Host "Creating storage context..." -ForegroundColor Yellow
    $storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageAccountKey
    Write-Host "✓ Storage context created" -ForegroundColor Green
    
    # Check if container exists, create if not
    Write-Host "`nChecking container existence..." -ForegroundColor Yellow
    $container = Get-AzStorageContainer -Name $ContainerName -Context $storageContext -ErrorAction SilentlyContinue
    
    if (-not $container) {
        Write-Host "Container '$ContainerName' not found. Creating..." -ForegroundColor Yellow
        New-AzStorageContainer -Name $ContainerName -Context $storageContext -Permission Off | Out-Null
        Write-Host "✓ Container created" -ForegroundColor Green
    } else {
        Write-Host "✓ Container exists" -ForegroundColor Green
    }
    
    # Upload each template file
    Write-Host "`n=== Uploading Template Files ===" -ForegroundColor Cyan
    $uploadedCount = 0
    $failedFiles = @()
    
    foreach ($blobName in $templateFiles.Keys) {
        $filePath = $templateFiles[$blobName]
        
        # Check if file exists
        if (-not (Test-Path $filePath)) {
            Write-Host "✗ File not found: $filePath" -ForegroundColor Red
            $failedFiles += $blobName
            continue
        }
        
        try {
            Write-Host "Uploading: $blobName..." -ForegroundColor Yellow
            
            # Upload file to blob storage (without .md extension in blob name)
            Set-AzStorageBlobContent -File $filePath `
                                     -Container $ContainerName `
                                     -Blob $blobName `
                                     -Context $storageContext `
                                     -Properties @{"ContentType"="text/markdown"} `
                                     -Force | Out-Null
            
            # Get file size for display
            $fileSize = [math]::Round((Get-Item $filePath).Length / 1KB, 1)
            
            Write-Host "  ✓ Uploaded: $blobName ($fileSize KB)" -ForegroundColor Green
            $uploadedCount++
            
        } catch {
            Write-Host "  ✗ Failed to upload $blobName : $($_.Exception.Message)" -ForegroundColor Red
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
            Write-Host "  📄 $($blob.Name) ($blobSize KB, Modified: $lastModified)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  No files found in container" -ForegroundColor Yellow
    }
    
    Write-Host "`n✓ Template upload process completed!" -ForegroundColor Green
    Write-Host "Your runbook can now access these templates from blob storage." -ForegroundColor Cyan
    
} catch {
    Write-Host "`n✗ Error during upload process:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Ensure you're connected to Azure: Connect-AzAccount" -ForegroundColor Gray
    Write-Host "2. Verify you have 'Storage Blob Data Contributor' role on the storage account" -ForegroundColor Gray
    Write-Host "3. Check that the storage account name is correct: $StorageAccountName" -ForegroundColor Gray
    Write-Host "4. Ensure the template files exist in the .\Templates\ directory" -ForegroundColor Gray
}

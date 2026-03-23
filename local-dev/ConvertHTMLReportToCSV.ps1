#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Converts MDM AI Analysis HTML reports to CSV format.

.DESCRIPTION
    This script extracts the "Strict Category Analysis Summary" section from the MDM AI Analysis HTML reports
    and converts it into a CSV file for easier data analysis and reporting.

.PARAMETER HtmlFilePath
    Path to the input HTML report file. If not specified, prompts to select from .\results folder.

.PARAMETER OutputCsvPath
    Path for the output CSV file. If not specified, creates CSV in the same directory with '_Summary.csv' suffix.

.EXAMPLE
    .\ConvertHTMLReportToCSV.ps1
    
.EXAMPLE
    .\ConvertHTMLReportToCSV.ps1 -HtmlFilePath ".\results\MDM_AI_Analysis_Report_102_Incidents_13_Categories_Stored_Data_15_Dec.html"
    
.EXAMPLE
    .\ConvertHTMLReportToCSV.ps1 -HtmlFilePath ".\results\report.html" -OutputCsvPath ".\exports\summary.csv"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$HtmlFilePath,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputCsvPath
)

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        'Info'    { 'White' }
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Get-HtmlReportFile {
    [CmdletBinding()]
    param()
    
    $resultsFolder = Join-Path $PSScriptRoot "results"
    
    if (-not (Test-Path $resultsFolder)) {
        Write-Log "Results folder not found: $resultsFolder" -Level Error
        return $null
    }
    
    $htmlFiles = Get-ChildItem -Path $resultsFolder -Filter "MDM_AI_Analysis_Report_*.html" | Sort-Object LastWriteTime -Descending
    
    if ($htmlFiles.Count -eq 0) {
        Write-Log "No HTML report files found in $resultsFolder" -Level Error
        return $null
    }
    
    Write-Host "`nAvailable HTML Reports:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $htmlFiles.Count; $i++) {
        $fileInfo = $htmlFiles[$i]
        Write-Host "  [$($i + 1)] $($fileInfo.Name) (Modified: $($fileInfo.LastWriteTime))" -ForegroundColor White
    }
    
    do {
        $selection = Read-Host "`nSelect a report number (1-$($htmlFiles.Count)) or press Enter for most recent"
        
        if ([string]::IsNullOrWhiteSpace($selection)) {
            return $htmlFiles[0].FullName
        }
        
        if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $htmlFiles.Count) {
            return $htmlFiles[[int]$selection - 1].FullName
        }
        
        Write-Log "Invalid selection. Please enter a number between 1 and $($htmlFiles.Count)" -Level Warning
    } while ($true)
}

function Extract-CategorySummaryFromHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HtmlContent
    )
    
    try {
        # Parse HTML content to extract category summary table
        $categoryData = @()
        $maxTickets = 0
        $tempData = @()
        
        # Find the table within the category summary section
        if ($HtmlContent -match '(?s)<h2[^>]*id="category-summary"[^>]*>.*?<table>(.*?)</table>') {
            $tableContent = $Matches[1]
            
            # Extract all table rows - First pass to find max tickets
            $rowMatches = [regex]::Matches($tableContent, '(?s)<tr[^>]*>(.*?)</tr>')
            
            foreach ($row in $rowMatches) {
                $rowContent = $row.Groups[1].Value
                
                # Skip header row
                if ($rowContent -match '<th') {
                    continue
                }
                
                # Skip total row
                if ($rowContent -match 'TOTAL PROCESSED' -or $rowContent -match 'total-row' -or $rowContent -match 'class="total-row"') {
                    continue
                }
                
                # Extract all TD cells from the row
                $cellMatches = [regex]::Matches($rowContent, '<td[^>]*>(.*?)</td>')
                
                if ($cellMatches.Count -ge 3) {
                    # First cell: Category name
                    $categoryName = $cellMatches[0].Groups[1].Value -replace '<[^>]+>', '' -replace '^\s+|\s+$', ''
                    
                    # Second cell: Count
                    $count = $cellMatches[1].Groups[1].Value -replace '<[^>]+>', '' -replace '^\s+|\s+$', ''
                    
                    # Third cell: Tickets
                    $ticketsHtml = $cellMatches[2].Groups[1].Value
                    
                    # Extract all ticket numbers from links
                    $ticketMatches = [regex]::Matches($ticketsHtml, "class='ticket-link'>([^<]+)</a>")
                    $tickets = @()
                    foreach ($ticketMatch in $ticketMatches) {
                        $tickets += $ticketMatch.Groups[1].Value
                    }
                    
                    # Only process if we have valid data
                    if ($categoryName -and $count -and $tickets.Count -gt 0) {
                        # Track max tickets
                        if ($tickets.Count -gt $maxTickets) {
                            $maxTickets = $tickets.Count
                        }
                        
                        # Store temp data
                        $tempData += @{
                            CategoryName = $categoryName
                            Count = [int]$count
                            Tickets = $tickets
                        }
                    }
                }
            }
            
            # Second pass: Create rows with individual ticket columns
            foreach ($item in $tempData) {
                # Create hashtable with Category and Count
                $row = [ordered]@{
                    Category = $item.CategoryName
                    Count = $item.Count
                }
                
                # Add ticket columns
                for ($i = 0; $i -lt $maxTickets; $i++) {
                    $ticketNum = $i + 1
                    if ($i -lt $item.Tickets.Count) {
                        $row["Ticket #$ticketNum"] = $item.Tickets[$i]
                    } else {
                        $row["Ticket #$ticketNum"] = ''
                    }
                }
                
                $categoryData += [PSCustomObject]$row
                
                # Add empty row for spacing between categories with "correct category" label
                $spacerRow = [ordered]@{
                    Category = "$($item.CategoryName) correct category"
                    Count = $null
                }
                
                for ($i = 0; $i -lt $maxTickets; $i++) {
                    $ticketNum = $i + 1
                    $spacerRow["Ticket #$ticketNum"] = ''
                }
                
                $categoryData += [PSCustomObject]$spacerRow
            }
        }
        else {
            Write-Log "Could not find category summary table in HTML content" -Level Error
            return $null
        }
        
        return $categoryData
        
    } catch {
        Write-Log "Error parsing HTML content: $($_.Exception.Message)" -Level Error
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
        return $null
    }
}

# Main script execution
try {
    Write-Log "Starting HTML to CSV conversion process..." -Level Info
    
    # Get HTML file path
    if ([string]::IsNullOrWhiteSpace($HtmlFilePath)) {
        $HtmlFilePath = Get-HtmlReportFile
        
        if ($null -eq $HtmlFilePath) {
            Write-Log "No HTML file selected. Exiting." -Level Error
            exit 1
        }
    }
    
    # Validate HTML file exists
    if (-not (Test-Path $HtmlFilePath)) {
        Write-Log "HTML file not found: $HtmlFilePath" -Level Error
        exit 1
    }
    
    Write-Log "Processing HTML file: $HtmlFilePath" -Level Info
    
    # Read HTML content
    $htmlContent = Get-Content -Path $HtmlFilePath -Raw -Encoding UTF8
    
    # Extract category summary data
    Write-Log "Extracting category summary data..." -Level Info
    $categoryData = Extract-CategorySummaryFromHtml -HtmlContent $htmlContent
    
    if ($null -eq $categoryData -or $categoryData.Count -eq 0) {
        Write-Log "No category data extracted from HTML file" -Level Error
        exit 1
    }
    
    Write-Log "Successfully extracted $($categoryData.Count) categories" -Level Success
    
    # Determine output CSV path
    if ([string]::IsNullOrWhiteSpace($OutputCsvPath)) {
        $htmlFileName = [System.IO.Path]::GetFileNameWithoutExtension($HtmlFilePath)
        $htmlDirectory = [System.IO.Path]::GetDirectoryName($HtmlFilePath)
        $OutputCsvPath = Join-Path $htmlDirectory "$($htmlFileName)_Summary.csv"
    }
    
    # Create output directory if it doesn't exist
    $outputDir = [System.IO.Path]::GetDirectoryName($OutputCsvPath)
    if (-not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        Write-Log "Created output directory: $outputDir" -Level Info
    }
    
    # Export to CSV
    Write-Log "Exporting to CSV: $OutputCsvPath" -Level Info
    $categoryData | Export-Csv -Path $OutputCsvPath -NoTypeInformation -Encoding UTF8
    
    Write-Log "CSV export completed successfully!" -Level Success
    Write-Log "Output file: $OutputCsvPath" -Level Success
    
    # Display summary
    Write-Host "`n" + "=" * 70 -ForegroundColor Cyan
    Write-Host "Conversion Summary" -ForegroundColor Cyan
    Write-Host "=" * 70 -ForegroundColor Cyan
    Write-Host "Input File:  $HtmlFilePath" -ForegroundColor White
    Write-Host "Output File: $OutputCsvPath" -ForegroundColor White
    Write-Host "Categories:  $($categoryData.Count)" -ForegroundColor White
    Write-Host "Total Tickets: $($categoryData | Measure-Object -Property Count -Sum | Select-Object -ExpandProperty Sum)" -ForegroundColor White
    Write-Host "=" * 70 -ForegroundColor Cyan
    
    # Display preview
    Write-Host "`nPreview of exported data:" -ForegroundColor Cyan
    $categoryData | Format-Table -AutoSize | Out-String | Write-Host
    
} catch {
    Write-Log "An unexpected error occurred: $($_.Exception.Message)" -Level Error
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}

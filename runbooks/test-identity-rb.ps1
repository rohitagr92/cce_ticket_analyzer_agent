# Ultra-simple test - just connect and report status
try {
    Write-Output "Connecting with managed identity..."
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    
    Write-Output "Getting current context..."
    $context = Get-AzContext
    Write-Output "Account: $($context.Account.Id)"
    Write-Output "Subscription: $($context.Subscription.Name)"
    Write-Output ""
    Write-Output "SUCCESS: Managed identity connection works!"
    
} catch {
    Write-Error "Failed to connect: $_"
    throw
}

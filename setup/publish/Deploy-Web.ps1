$env:HTTP_PROXY  = 'http://proxy-iind.intel.com:912'
$env:HTTPS_PROXY = $env:HTTP_PROXY
$env:NO_PROXY    = '127.0.0.1,localhost'
$env:SWA_CLI_DEPLOY_BINARY = "$env:USERPROFILE\.swa\deploy\StaticSitesClient.exe"

# Prefer explicit token from environment for least-privilege deployments.
$token = $env:SWA_DEPLOYMENT_TOKEN

if (-not $token) {
	try {
		$token = (Get-AzStaticWebAppSecret -ResourceGroupName 'OPSW-Ticket-Analyzer' -Name 'opsw-prodtools-reports').Property.AdditionalProperties['apiKey']
	} catch {
		Write-Warning "Could not read Static Web App secret via Az. If you do not have listSecrets permission, set SWA_DEPLOYMENT_TOKEN and rerun."
	}
}

if (-not $token) {
	throw "No deployment token available. Set SWA_DEPLOYMENT_TOKEN in your shell or request Microsoft.Web/staticSites/listSecrets/action access."
}

swa deploy .\web --deployment-token $token --env production

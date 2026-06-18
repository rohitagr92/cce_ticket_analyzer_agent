$env:HTTP_PROXY  = 'http://proxy-iind.intel.com:912'
$env:HTTPS_PROXY = $env:HTTP_PROXY
$env:NO_PROXY    = '127.0.0.1,localhost'
$env:SWA_CLI_DEPLOY_BINARY = "$env:USERPROFILE\.swa\deploy\StaticSitesClient.exe"
$token = (Get-AzStaticWebAppSecret -ResourceGroupName 'OPSW-Ticket-Analyzer' -Name 'opsw-prodtools-reports').Property.AdditionalProperties['apiKey']
swa deploy .\web --deployment-token $token --env production

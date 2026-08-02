# LocalConfig-ContentEngineering.psd1
# Non-secret settings for the Content Engineering service offering.
# Store secrets in LocalSecrets-ContentEngineering.psd1 (gitignored).

@{
    # Azure storage / local analysis defaults
    StorageAccountName        = "opswcontentenggblob"
    PromptTemplateContainerName = "templates"
    ResourceGroupName         = "OPSW-Ticket-Analyzer"
    SubscriptionId            = "1c6d384e-bc83-4b02-859c-76eeb87f7676"
    DataContainerName         = "data"
    ResultsContainerName      = "results"
    KeyVaultName              = "opswcontentenggkeyvault"

    # ServiceNow OAuth (same API gateway as Productivity Tools)
    ServiceNowClientID         = "6e7adbde-53d8-4993-8740-f658cba16a8b"
    ServiceNowScope            = "api://71c9ae16-9d10-45b7-9c1d-30925311dabf/.default"
    TokenUrl                   = "https://apis.intel.com/v1/auth/token"

    # Content Engineering ServiceNow scope IDs
    BusinessServiceId          = "a1de2ff2db8f50108062531dd3961911"   # End-User Collaboration (shared with PT)
    ServiceOfferingId          = "ce614555dbeb5c105447610ed39619f8"   # Content Engineering

    # Incidents API scoped to Content Engineering business_service + service_offering
    ServiceNowIncidentsURL = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=business_service=a1de2ff2db8f50108062531dd3961911^service_offering=ce614555dbeb5c105447610ed39619f8^stateIN6,7^ORDERBYDESCresolved_at&sysparm_display_value=true&sysparm_limit=1000"
    ServiceNowRequestsURL  = "https://apis.intel.com/itsm/api/now/table/sc_task?sysparm_query=business_service=a1de2ff2db8f50108062531dd3961911^service_offering=ce614555dbeb5c105447610ed39619f8^stateIN6,7^ORDERBYDESCresolved_at&sysparm_display_value=true&sysparm_limit=1000"

    # Local analysis workflow controls
    UseStoredIncidents       = $false
    StoredDataFileName       = $null
    DailyLookbackHours       = 26
    SaveRawDataLocally       = $true
    SaveRunArtifacts         = $true
    WeeklyMergeLookbackDays  = 7

    # Azure OpenAI (same instance as Productivity Tools)
    AzureOpenAIBaseUrl     = "https://opsw-ticket-analyzer-foundary.cognitiveservices.azure.com"
    AzureOpenAIModel       = "gpt-5.4-mini"
    AzureOpenAIDeployment  = "gpt-5.4-mini"
    AzureOpenAIApiVersion  = "2025-04-01-preview"
    AzureOpenAIApiKey      = $null   # set in LocalSecrets-ContentEngineering.psd1

    # Optional secret names used by the setup / Automation Account flow
    ServiceNowClientSecretName = "ContentEng-ServiceNowClientSecret"
    AzureOpenAIApiKeySecretName = "ContentEng-AzureOpenAIApiKey"
}

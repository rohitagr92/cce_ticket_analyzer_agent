# LocalConfig-EndUserConferencing.psd1
# Non-secret settings for the End User Conferencing service offering.
# Store secrets in LocalSecrets-EndUserConferencing.psd1 (gitignored).

@{
    # Azure storage / local analysis defaults
    StorageAccountName         = "opswconferblob"
    PromptTemplateContainerName = "templates"
    ResourceGroupName          = "OPSW-Ticket-Analyzer"
    SubscriptionId             = "1c6d384e-bc83-4b02-859c-76eeb87f7676"
    DataContainerName          = "data"
    ResultsContainerName       = "results"
    KeyVaultName               = "opswconferkeyvault"

    # ServiceNow OAuth
    ServiceNowClientID         = "6e7adbde-53d8-4993-8740-f658cba16a8b"
    ServiceNowScope            = "api://71c9ae16-9d10-45b7-9c1d-30925311dabf/.default"
    TokenUrl                   = "https://apis.intel.com/v1/auth/token"

    # End User Conferencing scope IDs
    BusinessServiceId          = "edde2ff2db8f50108062531dd3961911"
    MessagingServiceOfferingId = "56fb6c3a1b4da810bcb7326edc4bcbc3"
    RoomsServiceOfferingId     = "b4b18407dbcf50108062531dd39619e8"

    # Incidents API scoped to EUC offerings
    MessagingIncidentsURL      = ""
    RoomsIncidentsURL          = ""

    # Local analysis workflow controls
    UseStoredIncidents         = $false
    StoredDataFileName         = $null
    DailyLookbackDays          = 2
    SaveRawDataLocally         = $true
    SaveRunArtifacts           = $true
    WeeklyMergeLookbackDays    = 7

    # Azure OpenAI
    AzureOpenAIBaseUrl         = "https://opsw-ticket-analyzer-foundary.cognitiveservices.azure.com"
    AzureOpenAIModel           = "gpt-5.4-mini"
    AzureOpenAIDeployment      = "gpt-5.4-mini"
    AzureOpenAIApiVersion      = "2025-04-01-preview"
    AzureOpenAIApiKey          = $null   # set in LocalSecrets-EndUserConferencing.psd1

    # Optional secret names used by the setup / Automation Account flow
    ServiceNowClientSecretName  = "EndUserConferencing-ServiceNowClientSecret"
    AzureOpenAIApiKeySecretName  = "EndUserConferencing-AzureOpenAIApiKey"
}
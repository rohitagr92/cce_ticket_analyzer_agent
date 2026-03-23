# LocalConfig.psd1 - PowerShell native configuration
# This file contains your actual secrets and is ignored by git
# Copy this file as "LocalConfig.psd1" and fill in your real values below

@{
    # Azure Storage Settings
    PSD_AI_Automations_StorageAccountName = "YOUR_STORAGE_ACCOUNT_NAME"
    PSD_AI_Automations_PromptTemplateContainerName = "templates"
    PSD_AI_Automations_ResourceGroupName = "YOUR_RESOURCE_GROUP_NAME"
    Incidents_analyzer_SubscriptionId = "YOUR_SUBSCRIPTION_ID"

    # ServiceNow API Configuration
    ServiceNowIncidentsClientID = "YOUR_SERVICENOW_CLIENT_ID"
    ServiceNowIncidentsClientSecret = "YOUR_SERVICENOW_CLIENT_SECRET"
    ServiceNowIncidentsScope = "YOUR_SERVICENOW_SCOPE"
    TokenUrl = "https://YOUR_TOKEN_ENDPOINT/v1/auth/token"
    ServiceNowIncidentsURL = "https://YOUR_SERVICENOW_API/itsm/api/now/table/incident?sysparm_query=YOUR_QUERY&sysparm_display_value=true"
    ServiceNowRequestsURL = "https://YOUR_SERVICENOW_API/itsm/api/now/table/sc_task?sysparm_query=YOUR_QUERY&sysparm_display_value=true"

    # Azure OpenAI Settings
    AzureOpenAIBaseUrl = "https://YOUR_OPENAI_ENDPOINT.cognitiveservices.azure.com"
    AzureOpenAIDeployment = "gpt-4.1-nano"
    AzureOpenAIApiVersion = "2025-01-01-preview"
    AzureOpenAIApiKey = "YOUR_OPENAI_API_KEY"

    # Claude/Anthropic Settings (Alternative to OpenAI)
    UseClaudeModel = $true  # Set to $true to use Claude instead of OpenAI
    ClaudeEndpoint = "https://YOUR_AI_FOUNDRY_ENDPOINT.services.ai.azure.com/anthropic/v1/messages"
    ClaudeDeployment = "claude-sonnet-4-5"
    ClaudeApiKey = "YOUR_CLAUDE_API_KEY"
    ClaudeApiVersion = "2023-06-01"  # Anthropic API version

    # Webhook Configuration
    WebhookUrl = $null  # Set to your webhook endpoint URL if needed

    # Testing Configuration
    EnableBlobLogging = $false
    LogLevel = 'Debug'

    # Local Data Storage Configuration
    SaveRawDataLocally = $true
    UseStoredIncidents = $false  # Set to $true to use stored data instead of API calls
    StoredDataFileName = $null  # Leave null for latest file, or specify filename like "incidents_2025-11-25_14-30-00.json"

    # Processing Window and Weekly Merge Configuration
    DailyLookbackHours = 26  # Daily run window: last 24 hours + 2 hour safety buffer
    SaveRunArtifacts = $true  # Save each run output as JSON artifact for weekly merge
    GenerateWeeklyMergedReportOnWeekend = $false  # Legacy - no longer needed (merge now runs every day)
    WeeklyMergeLookbackDays = 7  # Number of days of artifacts to merge into weekly report
}

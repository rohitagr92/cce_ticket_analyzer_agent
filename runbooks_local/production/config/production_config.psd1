@{
    # Core Azure resources (change only when promoting to a new subscription/resource group)
    ResourceGroupName         = 'OPSW-Ticket-Analyzer'
    AutomationAccountName     = 'OPSW-ProductivityTools-account'
    StorageAccountName        = 'opswprodtoolsblob'
    ResultsContainerName      = 'results'
    TrendTableName            = 'IncidentsCategoryStats'

    # Runbook names (must match runbooks/ filenames without extension)
    AnalyzerRunbookName       = 'incident-analyzer-rb-prodtools'
    TrendRunbookName          = 'incident-trend-rb-prodtools'
    BackfillRunbookName       = 'incident-trend-backfill-rb-prodtools'
    ReconcileRunbookName      = 'incident-reconcile-rb-prodtools'

    # Scheduling / run parameters
    DailyLookbackHours        = 26    # analyzer: how many hours back to fetch resolved incidents
    AnalyzerRunHourUTC        = 2     # default local schedule hour (UTC) for analyzer wrapper
    TrendRunHourUTC           = 5     # default local schedule hour (UTC) for trend wrapper

    # Execution mode:
    #  - $true : call Azure Automation runbooks via Az.Automation (production / cloud)
    #  - $false: run the local runbook script file directly (development/testing)
    RunInAzureAutomation      = $true

    # Safety and limits
    MaxAiCallsPerIncident     = 3
    MaxIncidentsPerRun        = 1000

    # Optional: webhook for alerts (Logic App) - leave empty to disable
    LogicAppSendAIEmailWebHookURL = ''

    # Notes:
    # - Do NOT store secrets in this file. Keep secrets in Azure Automation encrypted variables
    #   or local secrets files when developing. This PSD1 is intentionally non-sensitive.
}

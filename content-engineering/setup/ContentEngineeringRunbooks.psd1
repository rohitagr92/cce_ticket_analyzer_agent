@{
    Runbooks = @(
        @{
            SourceFile   = '..\..\content-engineering\runbooks\incident-trend-backfill-rb-contenteng.ps1'
            RunbookName  = 'incident-trend-backfill-rb-contenteng'
            ScheduleName = 'IncidentTrendBackfill-ContentEng-Daily-0330UTC'
            RunHourUTC   = 3
            SkipSchedule = $false
        },
        @{
            SourceFile   = '..\..\content-engineering\runbooks\incident-analyzer-rb-contenteng.ps1'
            RunbookName  = 'incident-analyzer-rb-contenteng'
            ScheduleName = 'IncidentAnalyzer-ContentEng-Daily-0630UTC'
            RunHourUTC   = 6
            SkipSchedule = $false
        },
        @{
            SourceFile   = '..\..\content-engineering\runbooks\incident-trend-rb-contenteng.ps1'
            RunbookName  = 'incident-trend-rb-contenteng'
            ScheduleName = ''
            RunHourUTC   = 0
            SkipSchedule = $true
        }
    )
}

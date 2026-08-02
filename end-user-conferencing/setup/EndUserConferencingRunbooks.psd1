@{
    ServiceName = 'End User Conferencing'
    SharedAzureAssets = @{
        StorageAccountName   = 'opswconferblob'
        KeyVaultName         = 'opswconferkeyvault'
        AutomationAccountName = 'opswconferautomation'
    }
    ServiceOfferings = @(
        @{
            Name = 'Messaging - Teams Chat and Audio'
            Folder = '..\runbooks\messaging-teams-chat-audio'
            Runbooks = @(
                @{
                    SourceFile   = '..\runbooks\messaging-teams-chat-audio\incident-trend-backfill-rb-euc-messaging.ps1'
                    RunbookName  = 'incident-trend-backfill-rb-euc-messaging'
                    PublishedName = 'incident-trend-backfill-rb-euc-messaging'
                    ScheduleName  = 'IncidentTrendBackfill-EUC-Messaging-Daily-0330UTC'
                    RunHourUTC    = 3
                    SkipSchedule  = $false
                },
                @{
                    SourceFile   = '..\runbooks\messaging-teams-chat-audio\incident-analyzer-rb-euc-messaging.ps1'
                    RunbookName  = 'incident-analyzer-rb-euc-messaging'
                    PublishedName = 'incident-analyzer-rb-euc-messaging'
                    ScheduleName  = 'IncidentAnalyzer-EUC-Messaging-Daily-0630UTC'
                    RunHourUTC    = 6
                    SkipSchedule  = $false
                }
            )
        },
        @{
            Name = 'Meetings - Rooms and Hardware'
            Folder = '..\runbooks\meetings-rooms-hardware'
            Runbooks = @(
                @{
                    SourceFile   = '..\runbooks\meetings-rooms-hardware\incident-trend-backfill-rb-euc-rooms.ps1'
                    RunbookName  = 'incident-trend-backfill-rb-euc-rooms'
                    PublishedName = 'incident-trend-backfill-rb-euc-rooms'
                    ScheduleName  = 'IncidentTrendBackfill-EUC-Rooms-Daily-0330UTC'
                    RunHourUTC    = 3
                    SkipSchedule  = $false
                },
                @{
                    SourceFile   = '..\runbooks\meetings-rooms-hardware\incident-analyzer-rb-euc-rooms.ps1'
                    RunbookName  = 'incident-analyzer-rb-euc-rooms'
                    PublishedName = 'incident-analyzer-rb-euc-rooms'
                    ScheduleName  = 'IncidentAnalyzer-EUC-Rooms-Daily-0630UTC'
                    RunHourUTC    = 6
                    SkipSchedule  = $false
                }
            )
        }
    )
}

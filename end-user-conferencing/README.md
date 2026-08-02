# End User Conferencing

Service onboarding folder for the End User Conferencing business service.

Shared Azure assets:
- Storage account: `opswconferblob`
- Key Vault: `opswconferkeyvault`
- Automation account: `opswconferautomation`

Service offerings in this folder:
- [Messaging - Teams Chat and Audio](runbooks/messaging-teams-chat-audio/README.md)
- [Meetings - Rooms and Hardware](runbooks/meetings-rooms-hardware/README.md)

Templates:
- [templates](templates/README.md) contains the EUC prompt files that get uploaded to the shared templates container.
- [Messaging prompt set](templates/messaging-teams-chat-audio/README.md)
- [Rooms prompt set](templates/meetings-rooms-hardware/README.md)

Each prompt set now carries the full Prod Tools-style template pack for its offering.

Planned runbook set:
- 4 runbooks total, published to the same Automation Account
- The runbooks should stay isolated to this service only
- Other service offerings in this repository are not part of this onboarding set

Recommended pattern:
- Keep all service-specific files under this folder
- Reuse the same Azure resource group and dashboard pattern
- Store service-specific templates and secrets only for End User Conferencing

See `setup/EndUserConferencingRunbooks.psd1` for the runbook manifest.

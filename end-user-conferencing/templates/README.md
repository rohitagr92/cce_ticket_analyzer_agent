# End User Conferencing Templates

This folder holds the prompt templates used by the End User Conferencing runbooks.

It contains two separate prompt sets:
- `messaging-teams-chat-audio`
- `meetings-rooms-hardware`

Each set includes the same template types used in Prod Tools-style onboarding:
- `EnvironmentContext`
- `TicketCategorisation`
- `PossibleRootCause`
- `TrendSubCategorisation`
- `WorkNotesCleanup`
- `WorkNotesSummary`

Files in this folder are uploaded to the shared `templates` blob container during setup.

Suggested upload flow:
1. Run `setup\Setup-EndUserConferencing.ps1` to create or validate the shared Azure assets.
2. Upload the files in this folder to the `templates` container.
3. Publish the runbooks from `setup\Publish-EndUserConferencingRunbooks.ps1`.

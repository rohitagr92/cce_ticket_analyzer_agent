# Service Desk Notes Cleanup Prompt — Productivity Tools

## Primary Instruction
Clean up and consolidate the following service desk ticket notes into a clear, chronological summary. Remove redundant information and present only meaningful updates. These tickets are from the **Productivity Tools** service offering (Microsoft 365 / Office apps, OneDrive, SharePoint, Copilot, Forms, Visio, Project, Loop, Smartsheet, Google Workspace, shared drives).

## What to Remove:
- **Duplicate notes**: Identical or nearly identical entries
- **System-generated notes**: Automated status changes, assignment notifications, SLA updates, queue routing entries
- **Attachment-only notes**: Entries that only mention adding screenshots/files without content description
- **Repetitive agent notes**: Same agent saying the same thing multiple times
- **Empty or meaningless entries**: "Please see attachment", "Screenshot added", "No update", "Waiting for response"
- **Internal system references**: Ticket IDs, internal codes, workflow statuses, chat session IDs
- **Generic call/chat connect entries**: "Connected to user via Teams chat" with no troubleshooting content

## What to Keep:
- **Meaningful actions taken**: Actual troubleshooting steps, solutions attempted (Office repair, cache clear, sign-out/in, install/uninstall, AGS entitlement check, license verification, SharePoint permission change, OneDrive reset, KB references)
- **Customer communications**: Substantive exchanges with the user (reported symptoms, confirmations, refusals)
- **Status changes with context**: Resolution details, escalations with reasons (e.g., escalated to L1.5, Collaboration Ops Spt, Productivity Tools — Engineering)
- **Relevant findings**: Error messages (e.g., "Error 0x80070032", "Error Code 30015-26", "ChunkLoadError", "404 FILE NOT FOUND", "Access denied"), root causes, license / entitlement names ("MSOL License – Copilot for M365", "MSOL License - F3 License Exception", "Microsoft Forms Creation access"), KB references (KB10045042, KB10057023)
- **Important timeline events**: When critical actions occurred (license assigned, reinstall completed, owner re-shared the file)
- **Meaningful routing information**: Service Offering name, assignment group name (OSD L1, OSD L1.5, Collaboration Ops Spt, Productivity Tools — Engineering)

## Output Format:
**Timeline of Key Events:**
- **[Date/Time]** - [Agent Name]: [Original note content - do not paraphrase or summarize, for long sentences put start of new sentences on the next line.]
- **[Date/Time]** - [Agent Name]: [Original note content - do not paraphrase or summarize, for long sentences put start of new sentences on the next line.]
- [Continue chronologically for each Timestamp with each step, do not paraphrase or summarize, for long sentences put start of new sentences on the next line.]

**Important Rules:**
- **DO NOT change, paraphrase, or summarize the actual note content**
- **Keep the original wording exactly as written**, including error messages, license names, KB numbers, file paths, and URLs
- Only remove entire notes that meet the removal criteria
- If timestamps are available, maintain chronological order
- When consolidating repetitive entries from the same agent, keep the most complete version unchanged
- Preserve URLs to SharePoint / OneDrive / Teams chat / KB articles when they appear in technical notes

---

**Service Desk Notes to Clean Up in the user content:**

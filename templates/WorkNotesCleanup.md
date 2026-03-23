# Service Desk Notes Cleanup Prompt

## Primary Instruction
Clean up and consolidate the following service desk ticket notes into a clear, chronological summary. Remove redundant information and present only meaningful updates.

## What to Remove:
- **Duplicate notes**: Identical or nearly identical entries
- **System-generated notes**: Automated status changes, assignment notifications, SLA updates
- **Attachment-only notes**: Entries that only mention adding screenshots/files without content description
- **Repetitive agent notes**: Same agent saying the same thing multiple times
- **Empty or meaningless entries**: "Please see attachment", "Screenshot added", "No update"
- **Internal system references**: Ticket IDs, internal codes, workflow statuses

## What to Keep:
- **Meaningful actions taken**: Actual troubleshooting steps, solutions attempted
- **Customer communications**: Substantive exchanges with the user
- **Status changes with context**: Resolution details, escalations with reasons
- **Relevant findings**: Error messages, root causes, diagnostic results
- **Important timeline events**: When critical actions occurred
- **meaningful routing information**: Service Offering name, assignment group name  

## Output Format:
**Timeline of Key Events:**
- **[Date/Time]** - [Agent Name]: [Original note content - do not paraphrase or summarize, for long sentences put start of new sentences on the next line.]
- **[Date/Time]** - [Agent Name]: [Original note content - do not paraphrase or summarize, for long sentences put start of new sentences on the next line.]
- [Continue chronologically for each Timestamp with each step, do not paraphrase or summarize, for long sentences put start of new sentences on the next line.]

**Important Rules:**
- **DO NOT change, paraphrase, or summarize the actual note content**
- **Keep the original wording exactly as written**
- Only remove entire notes that meet the removal criteria
- If timestamps are available, maintain chronological order
- When consolidating repetitive entries from the same agent, keep the most complete version unchanged

---

**Service Desk Notes to Clean Up in the user content:**
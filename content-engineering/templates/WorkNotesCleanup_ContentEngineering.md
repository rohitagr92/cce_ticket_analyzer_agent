# WorkNotesCleanup — Content Engineering

## PURPOSE
Rules for cleaning raw ServiceNow work notes before AI analysis. Removes noise that would confuse categorization.

---

## CLEANUP RULES

**Remove automated system entries:**
- Lines starting with "Incident assigned to group" or "Incident reassigned"
- Lines starting with "Workflow advanced" or "Approval granted"
- Lines containing only timestamps with no human-written content
- Auto-generated CMS deployment log dumps (long blocks of JSON or XML)

**Remove PII and sensitive data:**
- Email addresses: replace with `[EMAIL]`
- Full names in signatures: replace with `[NAME]`
- Internal URLs containing authentication tokens: replace with `[URL]`

**Preserve:**
- All human-written descriptions of the issue
- Error messages and codes
- Steps already taken to resolve
- Confirmation of resolution

**Collapse repeated lines:**
If the same automated message appears 3 or more times consecutively, keep only the first occurrence and append `[repeated N times]`.

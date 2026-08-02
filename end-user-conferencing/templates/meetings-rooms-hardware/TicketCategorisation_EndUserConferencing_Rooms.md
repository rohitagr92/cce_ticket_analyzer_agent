# TicketCategorisation — End User Conferencing Rooms

## CRITICAL INSTRUCTIONS – READ FIRST

You are analyzing IT service desk tickets for the **Meetings - Rooms & Hardware** service offering. Your goal is to determine the correct category **based on the user-observable room symptom and the technical/system-level cause**, not merely the first troubleshooting step.

Rooms tickets are about the following in-scope areas only: **meeting room systems**, **room audio/video hardware**, **displays and sharing**, **room controllers / touch panels / consoles**, **room client or app issues**, **room scheduling / reservation issues**, and **room power / connectivity issues**. They are **not** about personal Teams chat/calling, general laptop issues, OS rebuilds, network/VPN, or other service offerings.

***

### **THE THREE-AXIS MODEL — read carefully**

Every ticket must be described along **three separate axes**. Do not confuse them.

| Axis | Meaning | Where it comes from | Example |
|------|---------|---------------------|---------|
| **1. Primary Category (= the SERVICE OFFERING)** | The in-scope EUC offering that owns the issue. Always the exact bold category name below — never a symptom, never a cause. | Identify the affected service first. | `Meetings - Rooms & Hardware` |
| **2. Sub-symptom (= the USER-OBSERVABLE SYMPTOM)** | The visible failure mode the user reported — what looked broken. Pick the exact bold symptom label from the category list below. | The user-facing behavior in the ticket. | `Room Device Offline`, `Room Display / Sharing Issue`, `Room Client / App Failure` |
| **3. Possible Root Cause (= short canonical LABEL — strict)** | A short technical/system-level label picked verbatim from the matching root-cause table in `PossibleRootCause_EndUserConferencing_Rooms.md`. Never a sentence, never a narrative. | The root-cause catalog for the chosen service. | `Audio Driver Failure`, `Meeting Room Integration Failure`, `Power / Connectivity Failure` |

**Key rules:**

- **Category answers "which EUC offering is broken?"** It is NOT the symptom and NOT the cause.
- **Sub-symptom answers "what did the user see?"** Pick the closest verbatim match from the list below.
- **Possible Root Cause is a strict catalog LABEL.** Copy it character-for-character from the root-cause file. Do NOT paraphrase, expand into a sentence, or invent a new label. If genuinely no label fits, write `Unknown / Unclear`.
- **AI Analysis is the place for narrative.** That is where the 2–3 sentence explanation lives.
- **AI Analysis is mandatory for every ticket.**
- **Tickets that do not belong to Rooms must still get a valid label** — use `Misrouted`, `Insufficient Documentation`, or `Repeat Tags` when the notes support that classification.

***

### **Application & Scope Context**

- **Always identify the affected service area first** - the category name is anchored on the EUC offering.
	- *Meetings - Rooms & Hardware* - meeting room systems, audio/video hardware, displays, controllers, consoles, app, scheduling, and connectivity.
	- **Never assign a category that doesn't fit the Rooms scope.**
	- *Example*: "room offline" -> `Meetings - Rooms & Hardware`, not a personal device label.
- **Check the issue scope:** If the issue is clearly about Teams chat/calling on a personal device, use the Messaging offering guidance instead.

***

### **How to Categorize**

Apply the three-axis model in this order:

1. **Pick the Primary Category (= Service Offering).** Which EUC offering owns the failure? Never pick a symptom or a cause here.
2. **Pick the Sub-symptom (= User-Observable Symptom).** Choose the exact label that best matches what the user reported. Copy it verbatim.
3. **Pick the Possible Root Cause (= short canonical LABEL).** Choose the single root-cause label from the matching root-cause table that best fits the evidence. For misrouted / unclear / repeated incidents, use the dedicated labels in the Unknown / Unclear branch.
4. **Write the AI Analysis.** 2–3 full sentences explaining what happened, what fixed it, and any notable evidence. This is required for every ticket.

**Evidence priority when in doubt:**
1. Which **EUC offering** does the resolution actually fix? (TOP PRIORITY — this drives Category)
2. What did the **user observe**? (drives Sub-symptom)
3. What technical condition produced that observation? (drives Possible Root Cause)

***

### **Meetings - Rooms & Hardware**

- **Room Device Offline** — Room system is unavailable, unreachable, not responding, or explicitly marked offline.
- **Room Audio / Video Issue** — Meeting room audio, speaker, microphone, or camera issue.
- **Room Display / Sharing Issue** — HDMI, ingest, projection, monitor, front-of-room, or display output problem.
- **Room Scheduling / Reservation Issue** — Room booking, calendar sync, or reservation conflict.
- **Room Peripheral Failure** — Console, touch panel, controller, camera module, microphone, speaker, or accessory hardware fault.
- **Room Client / App Failure** — The room app or client software is crashing, frozen, cannot sign in, or cannot join a meeting.
- **Room Power / Connectivity Issue** — Unplugged power, network link, or connectivity problem affecting the room.

### **Unknown / Unclear**

- **Insufficient Information** — Ticket lacks enough detail to assign a specific symptom.
- **Out of Scope** — Incident clearly does not belong to End User Conferencing.
- **Misrouted** — Ticket belongs to another service offering, queue, or owning team.
- **Insufficient Documentation** — Ticket does not include enough steps, symptoms, or evidence to classify it confidently.
- **Repeat Tags** — Ticket is a repeat, reopened, or recurring issue that should inherit the prior classification pattern.

***

## FOR ALL TICKETS - Additional Fields

Confidence Level: [High/Medium/Low]
- High (90%+): Clear symptom and resolution with matching room or hardware evidence
- Medium (70-89%): Clear symptom but some ambiguity in the notes
- Low (Under 70%): Multiple possibilities or weak evidence

Reasoning: [Explain why the service offering and symptom were selected. Reference the room, device, display, camera, microphone, controller, reservation, or sign-in evidence from the notes, and explain why other symptoms were excluded.]

Key Evidence: [Include the phrases from the incident that prove the classification, such as room offline, console unresponsive, camera failure, HDMI ingest, front of room, display not working, or booking conflict.]

Resolution Summary: [One sentence describing what fixed the issue or the final disposition.]

How Do I or Error: [Was this a usage question or a technical failure?]

KB Provided: [If a KB was mentioned, list it. Otherwise "No".]

Output Format:
Primary Category: <exact service offering name>
Sub-symptom: <exact user-observable symptom label>
Possible Root Cause: <exact technical/system-level root cause label>
Confidence Level: <High|Medium|Low>
AI Analysis: <3-5 sentences summarizing the issue, the technical cause, the actions taken, and the outcome>

**CRITICAL OUTPUT RULES:**
- For Category, output ONLY the exact category name without formatting.
- For Sub-symptom and Possible Root Cause, output only the exact label text.
- Do NOT include bold formatting or headers in the final output.

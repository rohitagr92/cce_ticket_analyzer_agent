## TrendSubCategorisation — Messaging - Teams Chat and Audio

### PURPOSE
Select exactly one user-observable symptom label for trend reporting. Do not use technical root-cause language.

### ALLOWED TREND LABELS
- Missing Chat History
- Chat / Message Loading
- Unable to Send Messages
- Unable to Receive Messages
- Delayed / Intermittent Messaging
- Deleted / Retention Message
- Group / Meeting / Channel Chat
- Conversation Switching
- Teams Status / Presence
- Notifications
- Microphone
- Speaker / Audio Output
- Headset / Bluetooth
- Audio Quality / Latency
- External / Federated Messaging
- Sign-In / Profile
- Voicemail
- Recording / Call History
- GIF / Rich Content
- File Sharing
- Read Receipts
- Contact / People Search
- Monitoring / Known Issue
- Policy / Expected Behavior
- Unknown / Unclear

### SELECTION GUIDANCE
- Missing Chat History: chat exists elsewhere or previously existed but is absent from the affected client.
- Chat / Message Loading: blank chat, latest-update loading, refresh error, temporarily unavailable, or conversation not opening.
- Unable to Send/Receive: explicit delivery failure in the stated direction.
- Delayed / Intermittent Messaging: messages eventually arrive or failure recurs intermittently.
- Deleted / Retention Message: deletion placeholder or retention-policy text is visible.
- Group / Meeting / Channel Chat: issue primarily concerns membership or visibility of those conversation types.
- Microphone, Speaker, Headset / Bluetooth, and Audio Quality: select the exact user-observable audio symptom.
- Monitoring / Known Issue: widespread or known product issue without a more useful individual symptom.

### RULES
1. Use the symptom reported by the user.
2. If several symptoms exist, select the one that caused the main impact or drove the final fix.
3. Web/desktop mismatch is evidence, not a trend label. Select the missing/loading/delivery symptom.
4. Output exactly one label with no explanation.

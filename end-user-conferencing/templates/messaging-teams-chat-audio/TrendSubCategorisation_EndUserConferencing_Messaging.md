# TrendSubCategorisation — End User Conferencing Messaging

## CRITICAL INSTRUCTIONS – READ FIRST

Use this file to choose one user-observable symptom label for Messaging trend grouping. Do not use root-cause language here.

## PURPOSE
Provide trend sub-symptom labels for Messaging incidents.

## RULES
- Use only the labels listed here.
- Output one label per incident trend row.
- Keep labels focused on the symptom seen in the incident data.

## SUB-SYMPTOM LABELS
- **Chat History Missing**
- **Old Chats Missing**
- **Recent Chats Missing**
- **Partial Chat History Missing**
- **Group Chats Missing**
- **Meeting Chats Missing**
- **Channels Missing**
- **Chats Not Loading**
- **Blank Chat Window**
- **Search Not Returning Results**
- **Message Send Failure**
- **Message Receive / Delivery Failure**
- **Audio / Microphone Failure**
- **Notifications Missing**
- **Presence / Status Issue**
- **Client Crash or Freeze**
- **Meeting Join Failure**
- **Calendar / Scheduling Failure**
- **Contacts / Directory Failure**
- **Call Log Missing**
- **Feature Disabled**
- **Unknown / Unclear**

## TRENDS TO EXPECT FROM THIS DATASET
- Chat history loss, old messages not reflecting, and missing conversations are the dominant trend.
- Message send failures and combined send/receive failures appear as a smaller but recurring pattern.
- Presence/status issues such as stuck Out of Office also recur.
- Audio and microphone issues exist but are less frequent than history/sync issues.

## CRITICAL OUTPUT RULES

- Output only one sub-symptom label.
- Do not include explanations or extra punctuation.
- Keep the label exactly as shown in the list above.

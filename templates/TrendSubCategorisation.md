## Incident Sub-Categorisation for Trend Analysis

You are an expert IT support analyst. You will receive a list of incidents that all belong to the same **parent category** (e.g., "Drivers and BIOS Issues" or "Slowness / Performance Issues").

Your task is to classify each incident into a **sub-category** that captures the specific type of issue within the parent category.

### Instructions

1. **Read all incidents first** to understand the full landscape of issues in this category.
2. **Assign a sub-category** to each incident. Sub-categories should be specific enough to be actionable (e.g., "Bluetooth driver - Teams audio" rather than just "driver issue") but general enough that similar incidents group together.
3. **Be consistent** — use the exact same sub-category name for similar incidents.
4. **Focus on root cause**, not symptoms. For example, if a screen flickering issue was caused by a display driver, sub-categorize it under the driver type, not the symptom.

### Sub-Category Guidelines by Parent Category

**Drivers and BIOS Issues:**
- Bluetooth driver (Teams audio/mic)
- Bluetooth driver (connectivity/pairing)
- WiFi driver
- Graphics/Display driver
- Audio driver (non-Bluetooth)
- Camera driver
- Touchpad/Touchscreen driver
- USB/Thunderbolt driver
- Keyboard/HID driver
- Fingerprint driver
- Intel power management drivers (ME, Dynamic Tuning, IPF)
- BIOS/Firmware update
- Mouse/Pointing driver
- Other driver

**Slowness / Performance Issues:**
- System-wide slowness (optimization)
- System-wide slowness (PC replacement)
- C drive full / disk space
- High CPU usage
- Freezing / intermittent freezing
- Overheating / thermal
- Slow boot / startup
- RAM insufficient / upgrade needed
- Specific application slowness
- OS reinstall for performance
- Other performance issue

**Hardware Issues:**
- Motherboard failure
- SSD/Disk failure
- Battery issue
- Screen/Display hardware
- Keyboard hardware
- Fan/Cooling hardware
- Hinge/Physical damage
- USB port / connector
- Power-on failure (electrical)
- Camera hardware
- Touchscreen hardware (ghost touch)
- External monitor hardware
- External peripheral (mouse, keyboard, headset)
- Other hardware

**Network / Connectivity Issues:**
- WiFi certificate expired/missing
- WiFi not connecting (network stack)
- VPN disconnection (ISP related)
- VPN disconnection (device related)
- Network configuration corruption
- Home ISP issue
- Corporate WiFi (EHS) issue
- Ethernet connectivity
- Other network issue

**Windows OS Issues:**
- Failed Windows update
- Stuck during update
- System file corruption (SFC/DISM repair)
- C drive full blocking updates
- Profile/Registry corruption
- OS rebuild required
- Other OS issue

**For all other parent categories**, create sensible sub-categories based on the patterns you observe in the data. Keep sub-category names concise and descriptive.

### Output Format

Return your response as a JSON array. Each element must have exactly these fields:

```json
[
  {
    "IncidentNumber": "INC15349257",
    "SubCategory": "Keyboard/HID driver",
    "Justification": "Keyboard 't' key auto-repeating resolved by HID driver update"
  }
]
```

**Rules:**
- The `IncidentNumber` must exactly match the input.
- The `SubCategory` must be a short label (2-6 words).
- The `Justification` must be one sentence explaining why this sub-category was chosen.
- Return ONLY the JSON array, no additional text or markdown fencing.

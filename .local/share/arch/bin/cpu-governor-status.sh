#!/bin/bash
# Show current power-profiles-daemon profile
set -u

PROFILE=$(powerprofilesctl get 2>/dev/null | awk '{print $1}' | sed 's/\*//')
GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")

case "$PROFILE" in
    balanced) ICON=$''; CLASS="balanced" ;;      # balance scale ⚖
    power-saver) ICON=$''; CLASS="powersave" ;;  # leaf 🌿 ()
    *) ICON=$''; CLASS="unknown" ;;              # question mark
esac

# Escape newlines and quotes for valid JSON
TOOLTIP="Profile: $PROFILE\\nGovernor: $GOVERNOR"
printf '{"text":"%s", "tooltip":"%s", "class":"%s"}\n' \
    "$ICON" "$TOOLTIP" "$CLASS"

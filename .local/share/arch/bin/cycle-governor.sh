#!/bin/bash
# Cycle power-profiles-daemon profile: balanced <-> power-saver
# Supports "reverse" argument for on-click-right
set -u

CURRENT=$(powerprofilesctl get 2>/dev/null | awk '{print $1}' | sed 's/\*//')

if [[ "${1:-}" == "reverse" ]]; then
    case "$CURRENT" in
        balanced) NEXT="power-saver" ;;
        power-saver) NEXT="balanced" ;;
        *) NEXT="balanced" ;;
    esac
else
    case "$CURRENT" in
        balanced) NEXT="power-saver" ;;
        power-saver) NEXT="balanced" ;;
        *) NEXT="balanced" ;;
    esac
fi

if powerprofilesctl set "$NEXT" 2>/dev/null; then
    logger -t waybar-governor "Switched to $NEXT"
    # Trigger immediate Waybar refresh via signal (RTMIN+1 = custom signal 1)
    pkill -RTMIN+1 waybar 2>/dev/null || true
else
    logger -t waybar-governor "Failed to switch to $NEXT"
    exit 1
fi

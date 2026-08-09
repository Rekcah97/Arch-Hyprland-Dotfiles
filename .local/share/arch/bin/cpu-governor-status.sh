#!/bin/bash
GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)

case "$GOVERNOR" in
    performance) ICON=$'\uf0e4' ;;
    ondemand|schedutil) ICON=$'\uf021' ;;
    powersave) ICON=$'\uf06c' ;;
    conservative) ICON=$'\uf013' ;;
    *) ICON=$'\uf013' ;;
esac

echo "{\"text\":\"$ICON\", \"tooltip\":\"Governor: $GOVERNOR\", \"class\":\"$GOVERNOR\"}"

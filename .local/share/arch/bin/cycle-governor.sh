#!/bin/bash
LOGFILE="/tmp/cycle-governor-debug.log"
echo "$(date '+%H:%M:%S') - cycle-governor.sh invoked" >> "$LOGFILE"

CURRENT=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
echo "$(date '+%H:%M:%S') - current governor: $CURRENT" >> "$LOGFILE"

case "$CURRENT" in
    performance) NEXT="ondemand" ;;
    ondemand) NEXT="powersave" ;;
    powersave) NEXT="performance" ;;
    *) NEXT="ondemand" ;;
esac

sudo -n /usr/local/bin/set-cpu-governor.sh "$NEXT" >> "$LOGFILE" 2>&1
echo "$(date '+%H:%M:%S') - switched to: $NEXT" >> "$LOGFILE"

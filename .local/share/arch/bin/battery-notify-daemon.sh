#!/bin/bash
#
# Event-driven battery notification daemon
# Reacts instantly to UPower events instead of polling every N seconds
#
# Install: ~/.local/share/arch/bin/battery-notify-daemon.sh

# ---------------- CONFIG ----------------
BATTERY="BAT0"
LOW_WARNING=20
LOW_CRITICAL=10
AUTO_SUSPEND_AT=5              # set to 0 to disable
CHARGE_LIMIT=80
NOTIFY_FULL=true
NOTIFY_PLUG_EVENTS=true
ENABLE_SOUND=true
ENABLE_POWER_PROFILE=true      # switch CPU governor to powersave at LOW_WARNING, ondemand when charging
LOG_FILE="$HOME/.local/share/battery-notify.log"
# -----------------------------------------

BAT_PATH="/sys/class/power_supply/$BATTERY"
FLAG_DIR="/tmp/battery-notify"
mkdir -p "$FLAG_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$LOG_FILE"
}

play_sound() {
    if [ "$ENABLE_SOUND" = true ]; then
        canberra-gtk-play -i battery-caution 2>/dev/null || \
        paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga 2>/dev/null
    fi
}

play_critical_sound() {
    if [ "$ENABLE_SOUND" = true ]; then
        if command -v play >/dev/null 2>&1; then
            play -n -q synth 0.1 sine 660 2>/dev/null
            play -n -q synth 0.1 sine 550 2>/dev/null
            play -n -q synth 0.1 sine 660 2>/dev/null
        else
            paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || \
            canberra-gtk-play -i battery-caution 2>/dev/null
        fi
    fi
}

set_power_profile() {
    local governor="$1"
    sudo -n /usr/local/bin/set-cpu-governor.sh "$governor" >/dev/null 2>&1
    log "CPU governor set to $governor"
}

check_battery() {
    CAPACITY=$(cat "$BAT_PATH/capacity")
    STATUS=$(cat "$BAT_PATH/status")

    PLUG_STATE_FILE="$FLAG_DIR/last_status"
    LAST_STATUS=""
    [ -f "$PLUG_STATE_FILE" ] && LAST_STATUS=$(cat "$PLUG_STATE_FILE")

    if [ "$NOTIFY_PLUG_EVENTS" = true ] && [ "$STATUS" != "$LAST_STATUS" ]; then
        if [ "$STATUS" = "Charging" ] && [ "$LAST_STATUS" != "" ]; then
            notify-send -u low "Charger Connected" "Battery at ${CAPACITY}%"
            log "Charger connected at ${CAPACITY}%"
            play_sound
        elif [ "$STATUS" = "Discharging" ] && [ "$LAST_STATUS" != "" ]; then
            notify-send -u low "Charger Disconnected" "Battery at ${CAPACITY}%"
            log "Charger disconnected at ${CAPACITY}%"
            play_sound
        fi
    fi
    echo "$STATUS" > "$PLUG_STATE_FILE"


    if [ "$STATUS" = "Charging" ]; then
        rm -f "$FLAG_DIR/notified_low_warning" "$FLAG_DIR/notified_low_critical" "$FLAG_DIR/notified_suspend"
        if [ "$ENABLE_POWER_PROFILE" = true ]; then
            set_power_profile "ondemand"
        fi
    elif [ "$STATUS" = "Discharging" ]; then
        rm -f "$FLAG_DIR/notified_charge_limit" "$FLAG_DIR/notified_full"
    fi

    if [ "$STATUS" = "Discharging" ]; then
        if [ "$AUTO_SUSPEND_AT" -gt 0 ] && [ "$CAPACITY" -le "$AUTO_SUSPEND_AT" ] && [ ! -f "$FLAG_DIR/notified_suspend" ]; then
            notify-send -u critical "Battery Critical - Suspending" "Battery at ${CAPACITY}%. Suspending system."
            log "Auto-suspend triggered at ${CAPACITY}%"
            touch "$FLAG_DIR/notified_suspend"
            play_sound
            sleep 5
            systemctl suspend
            return
        fi

        if [ "$CAPACITY" -le "$LOW_CRITICAL" ] && [ ! -f "$FLAG_DIR/notified_low_critical" ]; then
            notify-send -u critical "Battery Critical" "Battery at ${CAPACITY}%! Plug in now."
            log "Critical warning at ${CAPACITY}%"
            touch "$FLAG_DIR/notified_low_critical"
            play_critical_sound
        elif [ "$CAPACITY" -le "$LOW_WARNING" ] && [ ! -f "$FLAG_DIR/notified_low_warning" ]; then
            notify-send -u normal "Battery Low" "Battery at ${CAPACITY}%. Consider plugging in."
            log "Low warning at ${CAPACITY}%"
            touch "$FLAG_DIR/notified_low_warning"
            if [ "$ENABLE_POWER_PROFILE" = true ]; then
                set_power_profile "powersave"
            fi
        fi
    fi

    if [ "$STATUS" = "Charging" ]; then
        if [ "$CAPACITY" -ge "$CHARGE_LIMIT" ] && [ ! -f "$FLAG_DIR/notified_charge_limit" ]; then
            notify-send -u normal "Charge Limit Reached" "Battery at ${CAPACITY}%. Consider unplugging."
            log "Charge limit reminder at ${CAPACITY}%"
            touch "$FLAG_DIR/notified_charge_limit"
        fi
    fi

    if [ "$NOTIFY_FULL" = true ] && [ "$CAPACITY" -ge 100 ] && [ ! -f "$FLAG_DIR/notified_full" ]; then
        notify-send -u normal "Battery Full" "Battery fully charged. You can unplug now."
        log "Full charge reached"
        touch "$FLAG_DIR/notified_full"
    fi
}

# Run once immediately on start
check_battery

# Then listen for live UPower events and react instantly
upower --monitor-detail 2>/dev/null | while read -r line; do
    case "$line" in
        *"percentage"*|*"state"*|*"energy-rate"*)
            check_battery
            ;;
    esac
done
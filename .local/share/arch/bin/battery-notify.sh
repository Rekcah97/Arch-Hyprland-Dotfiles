#!/bin/bash
#
# Battery notification script for Arch Linux / Waybar setups
# Notifies on low battery (discharging) and charge limit (charging)
#
# Install: ~/.local/bin/battery-notify.sh
# Run via systemd timer every ~30-60s (see setup instructions)

# ---------------- CONFIG ----------------
BATTERY="BAT0"                 # change if yours is BAT1
LOW_WARNING=20                 # % - normal warning while discharging
LOW_CRITICAL=10                # % - critical warning while discharging
AUTO_SUSPEND_AT=5              # % - set to 0 to disable auto-suspend
CHARGE_LIMIT=80                # % - reminder to unplug while charging
NOTIFY_FULL=true               # notify at 100%
NOTIFY_PLUG_EVENTS=true        # notify when AC plugged/unplugged
ENABLE_SOUND=true              # play a sound on critical warning
LOG_FILE="$HOME/.local/share/battery-notify.log"
# -----------------------------------------

BAT_PATH="/sys/class/power_supply/$BATTERY"
FLAG_DIR="/tmp/battery-notify"
mkdir -p "$FLAG_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

if [ ! -d "$BAT_PATH" ]; then
    notify-send -u critical "Battery Script Error" "Battery path $BAT_PATH not found."
    exit 1
fi

CAPACITY=$(cat "$BAT_PATH/capacity")
STATUS=$(cat "$BAT_PATH/status")   # Charging / Discharging / Full / Not charging

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$LOG_FILE"
}

play_sound() {
    if [ "$ENABLE_SOUND" = true ]; then
        canberra-gtk-play -i battery-caution 2>/dev/null || \
        paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga 2>/dev/null
    fi
}

# ---- Plug/unplug event detection ----
PLUG_STATE_FILE="$FLAG_DIR/last_status"
LAST_STATUS=""
[ -f "$PLUG_STATE_FILE" ] && LAST_STATUS=$(cat "$PLUG_STATE_FILE")

if [ "$NOTIFY_PLUG_EVENTS" = true ] && [ "$STATUS" != "$LAST_STATUS" ]; then
    if [ "$STATUS" = "Charging" ] && [ "$LAST_STATUS" != "" ]; then
        notify-send -u low "Charger Connected" "Battery at ${CAPACITY}%"
        log "Charger connected at ${CAPACITY}%"
    elif [ "$STATUS" = "Discharging" ] && [ "$LAST_STATUS" != "" ]; then
        notify-send -u low "Charger Disconnected" "Battery at ${CAPACITY}%"
        log "Charger disconnected at ${CAPACITY}%"
    fi
fi
echo "$STATUS" > "$PLUG_STATE_FILE"

# ---- Reset flags on state change ----
if [ "$STATUS" = "Charging" ]; then
    rm -f "$FLAG_DIR/notified_low_warning" "$FLAG_DIR/notified_low_critical" "$FLAG_DIR/notified_suspend"
elif [ "$STATUS" = "Discharging" ]; then
    rm -f "$FLAG_DIR/notified_charge_limit" "$FLAG_DIR/notified_full"
fi

# ---- Discharging logic ----
if [ "$STATUS" = "Discharging" ]; then

    if [ "$AUTO_SUSPEND_AT" -gt 0 ] && [ "$CAPACITY" -le "$AUTO_SUSPEND_AT" ] && [ ! -f "$FLAG_DIR/notified_suspend" ]; then
        notify-send -u critical "Battery Critical - Suspending" "Battery at ${CAPACITY}%. Suspending system to prevent data loss."
        log "Auto-suspend triggered at ${CAPACITY}%"
        touch "$FLAG_DIR/notified_suspend"
        play_sound
        sleep 5
        systemctl suspend
        exit 0
    fi

    if [ "$CAPACITY" -le "$LOW_CRITICAL" ] && [ ! -f "$FLAG_DIR/notified_low_critical" ]; then
        notify-send -u critical "Battery Critical" "Battery at ${CAPACITY}%! Plug in now."
        log "Critical warning at ${CAPACITY}%"
        touch "$FLAG_DIR/notified_low_critical"
        play_sound
    elif [ "$CAPACITY" -le "$LOW_WARNING" ] && [ ! -f "$FLAG_DIR/notified_low_warning" ]; then
        notify-send -u normal "Battery Low" "Battery at ${CAPACITY}%. Consider plugging in."
        log "Low warning at ${CAPACITY}%"
        touch "$FLAG_DIR/notified_low_warning"
    fi
fi

# ---- Charging logic ----
if [ "$STATUS" = "Charging" ]; then

    if [ "$CAPACITY" -ge "$CHARGE_LIMIT" ] && [ ! -f "$FLAG_DIR/notified_charge_limit" ]; then
        notify-send -u normal "Charge Limit Reached" "Battery at ${CAPACITY}%. Consider unplugging for battery longevity."
        log "Charge limit reminder at ${CAPACITY}%"
        touch "$FLAG_DIR/notified_charge_limit"
    fi
fi

# ---- Full charge ----
if [ "$NOTIFY_FULL" = true ] && [ "$CAPACITY" -ge 100 ] && [ ! -f "$FLAG_DIR/notified_full" ]; then
    notify-send -u normal "Battery Full" "Battery fully charged. You can unplug now."
    log "Full charge reached"
    touch "$FLAG_DIR/notified_full"
fi

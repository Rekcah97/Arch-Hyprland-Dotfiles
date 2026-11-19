#!/bin/bash
#
# Battery notification script for Arch Linux / Waybar setups
# Notifies on low battery (discharging) and charge limit (charging)
# Run via systemd timer every ~30-60s

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

set -u

BAT_PATH="/sys/class/power_supply/$BATTERY"
FLAG_DIR="/tmp/battery-notify"
mkdir -p "$FLAG_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

if [ ! -d "$BAT_PATH" ]; then
    notify-send -u critical "Battery Script Error" "Battery path $BAT_PATH not found."
    exit 1
fi

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$LOG_FILE"
}

play_sound() {
    if [ "$ENABLE_SOUND" = true ]; then
        canberra-gtk-play -i battery-caution 2>/dev/null || \
        paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga 2>/dev/null
    fi
}

# Robust capacity read: trim whitespace, validate numeric
read_capacity() {
    local cap
    cap=$(cat "$BAT_PATH/capacity" 2>/dev/null | tr -d '[:space:]')
    [[ "$cap" =~ ^[0-9]+$ ]] || { log "Invalid capacity: '$cap'"; return 1; }
    echo "$cap"
}

# Robust status read (trim only leading/trailing whitespace, keep internal spaces like "Not charging")
read_status() {
    local status
    status=$(cat "$BAT_PATH/status" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -n "$status" ]] || { log "Invalid status: empty"; return 1; }
    echo "$status"
}

# Cross-check capacity against energy_now/energy_full
read_energy_pct() {
    local now full
    now=$(cat "$BAT_PATH/energy_now" 2>/dev/null | tr -d '[:space:]')
    full=$(cat "$BAT_PATH/energy_full" 2>/dev/null | tr -d '[:space:]')
    [[ "$now" =~ ^[0-9]+$ && "$full" =~ ^[0-9]+$ && "$full" -gt 0 ]] || return 1
    echo $(( now * 100 / full ))
}

# True critical: Discharging AND validated low capacity (debounced)
is_truly_critical() {
    local cap energy_pct
    cap=$(read_capacity) || return 1
    energy_pct=$(read_energy_pct) || return 1
    [[ "$cap" -le "$LOW_CRITICAL" && "$energy_pct" -le "$LOW_CRITICAL" ]]
}

is_truly_low() {
    local cap energy_pct
    cap=$(read_capacity) || return 1
    energy_pct=$(read_energy_pct) || return 1
    [[ "$cap" -le "$LOW_WARNING" && "$energy_pct" -le "$LOW_WARNING" ]]
}

# Separate check for auto-suspend: uses AUTO_SUSPEND_AT threshold with energy cross-check
is_truly_suspend() {
    local cap energy_pct
    cap=$(read_capacity) || return 1
    energy_pct=$(read_energy_pct) || return 1
    [[ "$cap" -le "$AUTO_SUSPEND_AT" && "$energy_pct" -le "$AUTO_SUSPEND_AT" ]]
}

maybe_notify() {
    local urgency="$1"
    local title="$2"
    local body="$3"
    local flag_file="$4"

    if [ ! -f "$flag_file" ]; then
        notify-send -u "$urgency" "$title" "$body"
        log "$title at $(read_capacity)%"
        touch "$flag_file"
        return 0
    fi
    return 1
}

# ---- Main check ----
capacity=$(read_capacity) || exit 1
status=$(read_status) || exit 1

# ---- Plug/unplug event detection ----
PLUG_STATE_FILE="$FLAG_DIR/last_status"
LAST_STATUS=""
[ -f "$PLUG_STATE_FILE" ] && LAST_STATUS=$(cat "$PLUG_STATE_FILE")

if [ "$NOTIFY_PLUG_EVENTS" = true ] && [ "$status" != "$LAST_STATUS" ]; then
    if [ "$status" = "Charging" ] && [ -n "$LAST_STATUS" ]; then
        notify-send -u low "Charger Connected" "Battery at ${capacity}%"
        log "Charger connected at ${capacity}%"
    elif [ "$status" = "Discharging" ] && [ -n "$LAST_STATUS" ]; then
        notify-send -u low "Charger Disconnected" "Battery at ${capacity}%"
        log "Charger disconnected at ${capacity}%"
    fi
fi
echo "$status" > "$PLUG_STATE_FILE"

# ---- Reset flags on state change ----
if [ "$status" = "Charging" ]; then
    rm -f "$FLAG_DIR/notified_low_warning" "$FLAG_DIR/notified_low_critical" "$FLAG_DIR/notified_suspend"
elif [ "$status" = "Discharging" ]; then
    rm -f "$FLAG_DIR/notified_charge_limit" "$FLAG_DIR/notified_full"
fi

# ---- Discharging logic ----
if [ "$status" = "Discharging" ]; then

    # Auto-suspend uses its own threshold with energy cross-check
    if [ "$AUTO_SUSPEND_AT" -gt 0 ] && is_truly_suspend && [ ! -f "$FLAG_DIR/notified_suspend" ]; then
        notify-send -u critical "Battery Critical - Suspending" "Battery at ${capacity}%. Suspending system to prevent data loss."
        log "Auto-suspend triggered at ${capacity}%"
        touch "$FLAG_DIR/notified_suspend"
        play_sound
        sleep 5
        systemctl suspend
        exit 0
    fi

    if is_truly_critical; then
        maybe_notify critical "Battery Critical" "Battery at ${capacity}%! Plug in now." \
            "$FLAG_DIR/notified_low_critical" && play_sound
    elif is_truly_low; then
        maybe_notify normal "Battery Low" "Battery at ${capacity}%. Consider plugging in." \
            "$FLAG_DIR/notified_low_warning"
    fi
fi

# ---- Charging logic ----
if [ "$status" = "Charging" ]; then

    if [ "$capacity" -ge "$CHARGE_LIMIT" ] && [ ! -f "$FLAG_DIR/notified_charge_limit" ]; then
        notify-send -u normal "Charge Limit Reached" "Battery at ${capacity}%. Consider unplugging for battery longevity."
        log "Charge limit reminder at ${capacity}%"
        touch "$FLAG_DIR/notified_charge_limit"
    fi
fi

# ---- Full charge ----
if [ "$NOTIFY_FULL" = true ] && [ "$capacity" -ge 100 ] && [ ! -f "$FLAG_DIR/notified_full" ]; then
    notify-send -u normal "Battery Full" "Battery fully charged. You can unplug now."
    log "Full charge reached"
    touch "$FLAG_DIR/notified_full"
fi
#!/bin/bash
#
# Event-driven battery notification daemon
# Reacts instantly to udev kernel events instead of polling
#
# Install: ~/.local/share/arch/bin/battery-notify-daemon.sh
# Run via systemd user service

# ---------------- CONFIG ----------------
BATTERY="BAT0"
AC_PATH="/sys/class/power_supply/ACAD"
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

# Single-instance lock
LOCK_FILE="/tmp/battery-notify.lock"
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "$(date '+%Y-%m-%d %H:%M:%S') | Another instance running, exiting" >> "$LOG_FILE"; exit 1; }

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$LOG_FILE"
}

play_sound() {
    [ "$ENABLE_SOUND" = true ] || return
    local f
    case "${1:-}" in
        plug)   f=/usr/share/sounds/freedesktop/stereo/power-plug.oga ;;
        unplug) f=/usr/share/sounds/freedesktop/stereo/power-unplug.oga ;;
        *)      f=/usr/share/sounds/freedesktop/stereo/dialog-warning.oga ;;
    esac
    ( pw-play "$f" 2>/dev/null || paplay "$f" 2>/dev/null ) 9>&- &
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
    [ "$(cat "$FLAG_DIR/governor" 2>/dev/null)" = "$governor" ] && return
    sudo -n /usr/local/bin/set-cpu-governor.sh "$governor" >/dev/null 2>&1
    echo "$governor" > "$FLAG_DIR/governor"
    log "CPU governor set to $governor"
}

# Robust capacity read: trim whitespace, validate numeric, safe default
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

# Cross-check capacity against energy_now/energy_full (debounce: both must agree)
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

WAYBAR_JSON="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/waybar-battery.json"
WAYBAR_SCRIPT="$HOME/.config/waybar/scripts/battery-tooltip.py"

update_waybar() {
    python3 "$WAYBAR_SCRIPT" > "$WAYBAR_JSON.tmp" 2>/dev/null \
        && mv "$WAYBAR_JSON.tmp" "$WAYBAR_JSON"
    pkill -RTMIN+8 waybar
}

_check_battery() {
    local capacity status ac LAST_AC

    capacity=$(read_capacity) || return
    status=$(read_status) || return

    ac=$(cat "$AC_PATH/online" 2>/dev/null)
    LAST_AC=$(cat "$FLAG_DIR/last_ac" 2>/dev/null)
    if [ "$NOTIFY_PLUG_EVENTS" = true ] && [ -n "$LAST_AC" ] && [ "$ac" != "$LAST_AC" ]; then
        if [ "$ac" = "1" ]; then
            notify-send -u low "Charger Connected" "Battery at ${capacity}%"
            play_sound plug
        else
            notify-send -u low "Charger Disconnected" "Battery at ${capacity}%"
            play_sound unplug
        fi
    fi
    echo "$ac" > "$FLAG_DIR/last_ac"

    update_waybar
    if [ "$ac" != "$LAST_AC" ]; then
        ( sleep 2; update_waybar ) 9>&- 8>&- &   # catch BAT0 settling
    fi

    local PLUG_STATE_FILE="$FLAG_DIR/last_status"
    local LAST_STATUS=""
    [ -f "$PLUG_STATE_FILE" ] && LAST_STATUS=$(cat "$PLUG_STATE_FILE")
    echo "$status" > "$PLUG_STATE_FILE"

    # Reset flags on state change
    if [ "$status" = "Charging" ]; then
        rm -f "$FLAG_DIR/notified_low_warning" "$FLAG_DIR/notified_low_critical" "$FLAG_DIR/notified_suspend"
        if [ "$ENABLE_POWER_PROFILE" = true ]; then
            set_power_profile "ondemand"
        fi
    elif [ "$status" = "Discharging" ]; then
        rm -f "$FLAG_DIR/notified_charge_limit"
        # Only clear notified_full if battery is below 100%
        if [ "$capacity" -lt 100 ]; then
            rm -f "$FLAG_DIR/notified_full"
        fi
    fi

    # Discharging logic with debounced checks
    if [ "$status" = "Discharging" ]; then
        # Auto-suspend uses its own threshold with energy cross-check
        if [ "$AUTO_SUSPEND_AT" -gt 0 ] && is_truly_suspend && [ ! -f "$FLAG_DIR/notified_suspend" ]; then
            notify-send -u critical "Battery Critical - Suspending" "Battery at ${capacity}%. Suspending system."
            log "Auto-suspend triggered at ${capacity}%"
            touch "$FLAG_DIR/notified_suspend"
            play_sound
            sleep 5
            systemctl suspend
            return
        fi

        if is_truly_critical; then
            maybe_notify critical "Battery Critical" "Battery at ${capacity}%! Plug in now." \
                "$FLAG_DIR/notified_low_critical" && play_critical_sound
        elif is_truly_low; then
            maybe_notify normal "Battery Low" "Battery at ${capacity}%. Consider plugging in." \
                "$FLAG_DIR/notified_low_warning"
            if [ "$ENABLE_POWER_PROFILE" = true ]; then
                set_power_profile "powersave"
            fi
        fi
    fi

    # Charging logic
    if [ "$status" = "Charging" ]; then
        if [ "$capacity" -ge "$CHARGE_LIMIT" ] && [ ! -f "$FLAG_DIR/notified_charge_limit" ]; then
            notify-send -u normal "Charge Limit Reached" "Battery at ${capacity}%. Consider unplugging."
            log "Charge limit reminder at ${capacity}%"
            touch "$FLAG_DIR/notified_charge_limit"
        fi
    fi

    # Full charge
    if [ "$NOTIFY_FULL" = true ] && [ "$capacity" -ge 100 ] && [ ! -f "$FLAG_DIR/notified_full" ]; then
        notify-send -u normal "Battery Full" "Battery fully charged. You can unplug now."
        log "Full charge reached"
        touch "$FLAG_DIR/notified_full"
    fi
}

# Serialize runs: udev events and the poll loop can fire at the same moment,
# and both would otherwise see the old last_ac and notify twice.
check_battery() {
    (
        flock 8
        _check_battery
    ) 8>"$FLAG_DIR/check.lock"
}

cleanup() {
    log "Daemon stopping"
    kill "$UDEV_PID" "$POLL_PID" "$WB_PID" 2>/dev/null
    exit 0
}
trap cleanup INT TERM

check_battery

stdbuf -oL udevadm monitor --subsystem-match=power_supply --kernel 2>/dev/null | while read -r line; do
    check_battery
done 9>&- &
UDEV_PID=$!

while sleep 30; do
    check_battery
done 9>&- &
POLL_PID=$!

while sleep 5; do
    update_waybar
done 9>&- &
WB_PID=$!

wait
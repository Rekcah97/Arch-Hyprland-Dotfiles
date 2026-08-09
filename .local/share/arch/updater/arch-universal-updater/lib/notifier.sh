#!/usr/bin/env bash
# =============================================================================
# lib/notifier.sh - Desktop notifications via notify-send
# =============================================================================

[[ -n "${ARCH_UPDATER_NOTIFIER_LOADED:-}" ]] && return 0
ARCH_UPDATER_NOTIFIER_LOADED=1

# ---------------------------------------------------------------------------
# notifier::send <title> <message> [urgency]
# ---------------------------------------------------------------------------
notifier::send() {
    local title="$1" message="$2" urgency="${3:-normal}"

    [[ "${NOTIFICATIONS_ENABLED:-true}" == "true" ]] || return 0
    util::require_cmd notify-send || return 0

    notify-send -u "$urgency" -a "Arch Universal Updater" "$title" "$message" >/dev/null 2>&1 &
}

notifier::finished() {
    [[ "${NOTIFY_ON_FINISH:-true}" == "true" ]] || return 0
    notifier::send "Updates Finished" "$1" "normal"
}

notifier::failed() {
    [[ "${NOTIFY_ON_FAILURE:-true}" == "true" ]] || return 0
    notifier::send "Updates Failed" "$1" "critical"
}

notifier::retry_complete() {
    [[ "${NOTIFY_ON_RETRY_COMPLETE:-true}" == "true" ]] || return 0
    notifier::send "Retry Complete" "$1" "normal"
}

notifier::cleanup_complete() {
    [[ "${NOTIFY_ON_CLEANUP:-true}" == "true" ]] || return 0
    notifier::send "Cleanup Complete" "$1" "low"
}

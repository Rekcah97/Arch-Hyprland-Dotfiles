#!/usr/bin/env bash
# =============================================================================
# lib/logger.sh - File logging and log archival
# =============================================================================
# Writes structured log lines to logs/latest.log and archives the previous
# run's log before a new one starts. Every log line includes a timestamp,
# level, source manager, package name/version (when relevant), and message.
# =============================================================================

[[ -n "${ARCH_UPDATER_LOGGER_LOADED:-}" ]] && return 0
ARCH_UPDATER_LOGGER_LOADED=1

LOGGER_ACTIVE_PATH=""

# ---------------------------------------------------------------------------
# logger::init <log_dir> <log_file> <archive_count> - archive the previous
# log file and open a fresh one for this run.
# ---------------------------------------------------------------------------
logger::init() {
    local log_dir="$1" log_file="$2" archive_count="${3:-10}"

    util::mkdir_safe "$log_dir"
    util::mkdir_safe "$log_dir/archive"

    local active="$log_dir/$log_file"

    if [[ -f "$active" ]]; then
        local stamp
        stamp="$(date '+%Y%m%d-%H%M%S')"
        mv -f "$active" "$log_dir/archive/${log_file%.log}-${stamp}.log"

        # Trim old archives beyond archive_count.
        local archives
        mapfile -t archives < <(ls -1t "$log_dir/archive" 2>/dev/null)
        if (( ${#archives[@]} > archive_count )); then
            local i
            for (( i = archive_count; i < ${#archives[@]}; i++ )); do
                rm -f "$log_dir/archive/${archives[$i]}"
            done
        fi
    fi

    LOGGER_ACTIVE_PATH="$active"
    : > "$LOGGER_ACTIVE_PATH"
    logger::write "INFO" "SYSTEM" "-" "-" "Arch Universal Updater session started"
}

# ---------------------------------------------------------------------------
# logger::write <level> <source> <package> <version> <message> [duration]
# ---------------------------------------------------------------------------
logger::write() {
    local level="$1" source_mgr="$2" pkg="${3:--}" ver="${4:--}" msg="$5" duration="${6:--}"
    [[ -z "$LOGGER_ACTIVE_PATH" ]] && return 0
    printf '[%s] [%-5s] [%-8s] pkg=%-30s ver=%-15s dur=%-8s %s\n' \
        "$(util::now_iso)" "$level" "$source_mgr" "$pkg" "$ver" "$duration" "$msg" \
        >> "$LOGGER_ACTIVE_PATH"
}

# ---------------------------------------------------------------------------
# logger::info / warn / error / success - convenience wrappers
# ---------------------------------------------------------------------------
logger::info()    { logger::write "INFO"    "$1" "${2:-}" "${3:-}" "${4:-}" "${5:-}"; }
logger::warn()    { logger::write "WARN"    "$1" "${2:-}" "${3:-}" "${4:-}" "${5:-}"; }
logger::error()   { logger::write "ERROR"   "$1" "${2:-}" "${3:-}" "${4:-}" "${5:-}"; }
logger::success() { logger::write "SUCCESS" "$1" "${2:-}" "${3:-}" "${4:-}" "${5:-}"; }

# ---------------------------------------------------------------------------
# logger::path - print the active log file path
# ---------------------------------------------------------------------------
logger::path() {
    printf '%s' "$LOGGER_ACTIVE_PATH"
}

# ---------------------------------------------------------------------------
# logger::tail <n> - print the last n lines of the active log
# ---------------------------------------------------------------------------
logger::tail() {
    local n="${1:-10}"
    [[ -f "$LOGGER_ACTIVE_PATH" ]] && tail -n "$n" "$LOGGER_ACTIVE_PATH"
}

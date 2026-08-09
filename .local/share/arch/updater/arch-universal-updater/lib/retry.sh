#!/usr/bin/env bash
# =============================================================================
# lib/retry.sh - Automatic retry wrapper for failed package operations
# =============================================================================
# Wraps an arbitrary command, retrying up to RETRY_COUNT times with a
# RETRY_DELAY pause between attempts. Used by pacman.sh/yay.sh/flatpak.sh so
# a single flaky download doesn't abort the whole update run.
# =============================================================================

[[ -n "${ARCH_UPDATER_RETRY_LOADED:-}" ]] && return 0
ARCH_UPDATER_RETRY_LOADED=1

# ---------------------------------------------------------------------------
# retry::run <max_attempts> <delay_seconds> <cmd...> - run a command, retrying
# on nonzero exit. Returns the final exit code and prints the number of
# attempts actually used to stderr as "ATTEMPTS=<n>" for the caller to parse.
# ---------------------------------------------------------------------------
retry::run() {
    local max_attempts="$1" delay="$2"; shift 2
    local attempt=1
    local rc=0

    while (( attempt <= max_attempts )); do
        if "$@"; then
            echo "ATTEMPTS=$attempt" >&2
            return 0
        fi
        rc=$?
        if (( attempt < max_attempts )); then
            sleep "$delay"
        fi
        (( attempt++ ))
    done

    echo "ATTEMPTS=$max_attempts" >&2
    return "$rc"
}

# ---------------------------------------------------------------------------
# retry::should_auto_retry - reflects the AUTO_RETRY config flag
# ---------------------------------------------------------------------------
retry::should_auto_retry() {
    [[ "${AUTO_RETRY:-true}" == "true" ]]
}

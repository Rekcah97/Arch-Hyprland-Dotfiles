#!/usr/bin/env bash
# =============================================================================
# lib/pacman.sh - Pacman detection, update checking, and update execution
# =============================================================================
# This module never draws anything to the screen. It only updates state
# files (via lib/cache.sh) so the dashboard (lib/dashboard.sh) can render
# live progress. This keeps update logic and UI cleanly separated.
# =============================================================================

[[ -n "${ARCH_UPDATER_PACMAN_LOADED:-}" ]] && return 0
ARCH_UPDATER_PACMAN_LOADED=1

# ---------------------------------------------------------------------------
# pacman::available - returns 0 if pacman exists on this system
# ---------------------------------------------------------------------------
pacman::available() {
    util::require_cmd pacman
}

# ---------------------------------------------------------------------------
# pacman::check_updates - print one "name old_ver -> new_ver" line per pending
# update. Uses `checkupdates` (pacman-contrib) when available since it is
# sync-DB safe without needing root; falls back to `pacman -Qu`.
# ---------------------------------------------------------------------------
pacman::check_updates() {
    if util::require_cmd checkupdates; then
        checkupdates 2>/dev/null
    else
        pacman -Qu 2>/dev/null
    fi
}

# ---------------------------------------------------------------------------
# pacman::update_count - number of pending pacman updates
# ---------------------------------------------------------------------------
pacman::update_count() {
    pacman::check_updates | grep -c . || true
}

# ---------------------------------------------------------------------------
# pacman::_map_state <line> - translate a raw pacman output line into one of
# the documented package states: Waiting, Downloading, Verifying, Installing,
# Running Hooks, Finished. Prints nothing if the line doesn't match a known
# transition (caller keeps the previous state in that case).
# ---------------------------------------------------------------------------
pacman::_map_state() {
    local line="$1"
    case "$line" in
        *downloading*|*"retrieving packages"*) echo "Downloading" ;;
        *"checking keyring"*|*"checking package integrity"*|*"loading package files"*|*"checking for file conflicts"*|*"checking available disk space"*) echo "Verifying" ;;
        *"installing "*|*"upgrading "*|*"reinstalling "*|*"Processing package changes"*) echo "Installing" ;;
        *"Running post-transaction hooks"*|*"Running pre-transaction hooks"*) echo "Running Hooks" ;;
        *) echo "" ;;
    esac
}

# ---------------------------------------------------------------------------
# pacman::run_updates <state_dir> - execute the full pacman sync+upgrade,
# streaming state into cache/state/pacman.state as it progresses. Returns
# the number of failures observed (0 = success).
# ---------------------------------------------------------------------------
pacman::run_updates() {
    local state_dir="$1"
    local total completed=0 failed=0
    local pkg_list
    pkg_list="$(pacman::check_updates)"
    total="$(printf '%s\n' "$pkg_list" | grep -c . || true)"
    [[ -z "$total" ]] && total=0

    cache::set_many "$state_dir" "pacman" \
        "STATUS=Waiting" "CURRENT_PKG=-" "CURRENT_PCT=0" "OVERALL_PCT=0" \
        "COMPLETED=0" "TOTAL=$total" "SPEED=0 B/s" "REMAINING=0 B" "ETA=--:--:--" \
        "FAILED_COUNT=0"

    if (( total == 0 )); then
        cache::set_many "$state_dir" "pacman" "STATUS=Finished" "OVERALL_PCT=100"
        logger::info "PACMAN" "-" "-" "No pending pacman updates"
        return 0
    fi

    logger::info "PACMAN" "-" "-" "Starting update of $total package(s)"

    local start_epoch
    start_epoch="$(util::now_epoch)"

    local sudo_cmd="sudo"
    util::require_cmd sudo || sudo_cmd=""

    # --noprogressbar keeps pacman's output line-based so it can be parsed
    # safely without dealing with carriage-return redraws.
    local fifo
    fifo="$(mktemp -u "${state_dir}/pacman_stream.XXXXXX")"
    mkfifo "$fifo"

    ( $sudo_cmd pacman -Syu --noconfirm --noprogressbar > "$fifo" 2>&1; echo "__PACMAN_EXIT_$?__" >> "$fifo" ) &

    local cur_state="Waiting"
    local exit_code=0
    local current_pkg="-"

    # Open the fifo for reading. Because the writer subshell above holds it
    # open too, this read loop blocks until output arrives and only sees EOF
    # once the writer exits (after appending its exit marker line).
    exec 9< "$fifo"
    while IFS= read -r -u 9 line; do
        if [[ "$line" =~ ^__PACMAN_EXIT_([0-9]+)__$ ]]; then
            exit_code="${BASH_REMATCH[1]}"
            continue
        fi

        local mapped
        mapped="$(pacman::_map_state "$line")"
        [[ -n "$mapped" ]] && cur_state="$mapped"

        # Track "(x/y) message" transaction counters pacman prints for each
        # installing/upgrading step to derive overall progress.
        if [[ "$line" =~ \(([0-9]+)/([0-9]+)\)\ (installing|upgrading|reinstalling)\ ([^\.]+) ]]; then
            completed="${BASH_REMATCH[1]}"
            total="${BASH_REMATCH[2]}"
            current_pkg="${BASH_REMATCH[4]}"
            local overall_pct
            overall_pct="$(util::percent "$completed" "$total")"
            cache::set_many "$state_dir" "pacman" \
                "STATUS=$cur_state" "CURRENT_PKG=$current_pkg" "CURRENT_PCT=100" \
                "OVERALL_PCT=$overall_pct" "COMPLETED=$completed" "TOTAL=$total"
            cache::append_completed "$state_dir" "pacman" "$current_pkg" "-"
            logger::success "PACMAN" "$current_pkg" "-" "installed"
        elif [[ "$line" =~ ^downloading\ (.+)\.\.\.$ ]]; then
            current_pkg="${BASH_REMATCH[1]}"
            cache::set_many "$state_dir" "pacman" "STATUS=Downloading" "CURRENT_PKG=$current_pkg"
        elif [[ -n "$mapped" ]]; then
            cache::set "$state_dir" "pacman" "STATUS" "$cur_state"
        fi

        if [[ "$line" =~ error:|failed ]]; then
            (( failed++ ))
            cache::append_failure "$state_dir" "pacman" "$current_pkg" "$line" "0"
            cache::set "$state_dir" "pacman" "FAILED_COUNT" "$failed"
            logger::error "PACMAN" "$current_pkg" "-" "$line"
        fi

        local elapsed=$(( $(util::now_epoch) - start_epoch ))
        cache::set "$state_dir" "pacman" "ELAPSED" "$elapsed"
    done
    exec 9<&-
    rm -f "$fifo"

    cache::set_many "$state_dir" "pacman" "STATUS=Finished" "OVERALL_PCT=100"
    logger::info "PACMAN" "-" "-" "Pacman update pass complete ($failed failure(s), exit=$exit_code)"
    return "$failed"
}

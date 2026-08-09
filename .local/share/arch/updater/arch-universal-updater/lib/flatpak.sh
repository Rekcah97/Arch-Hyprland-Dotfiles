#!/usr/bin/env bash
# =============================================================================
# lib/flatpak.sh - Flatpak detection, update checking, and execution
# =============================================================================

[[ -n "${ARCH_UPDATER_FLATPAK_LOADED:-}" ]] && return 0
ARCH_UPDATER_FLATPAK_LOADED=1

# ---------------------------------------------------------------------------
# flatpak::available
# ---------------------------------------------------------------------------
flatpak::available() {
    util::require_cmd flatpak
}

# ---------------------------------------------------------------------------
# flatpak::check_updates - one ref per line with a pending update
# ---------------------------------------------------------------------------
flatpak::check_updates() {
    flatpak::available || return 1
    flatpak remote-ls --updates --columns=application 2>/dev/null
}

# ---------------------------------------------------------------------------
# flatpak::update_count
# ---------------------------------------------------------------------------
flatpak::update_count() {
    flatpak::check_updates | grep -c . || true
}

# ---------------------------------------------------------------------------
# flatpak::_map_state <line>
# ---------------------------------------------------------------------------
flatpak::_map_state() {
    local line="$1"
    case "$line" in
        *"Downloading"*)  echo "Downloading" ;;
        *"Installing"*)   echo "Installing" ;;
        *"Deploying"*)    echo "Deploying" ;;
        *"Pruning"*|*"Cleaning"*) echo "Cleaning" ;;
        *) echo "" ;;
    esac
}

# ---------------------------------------------------------------------------
# flatpak::run_updates <state_dir> - runs `flatpak update -y`, streaming
# progress into cache/state/flatpak.state.
# ---------------------------------------------------------------------------
flatpak::run_updates() {
    local state_dir="$1"

    if ! flatpak::available; then
        cache::set_many "$state_dir" "flatpak" "STATUS=Finished" "OVERALL_PCT=100" "TOTAL=0" "COMPLETED=0"
        logger::info "FLATPAK" "-" "-" "flatpak not installed, skipping"
        return 0
    fi

    local total completed=0 failed=0
    total="$(flatpak::update_count)"
    [[ -z "$total" ]] && total=0

    cache::set_many "$state_dir" "flatpak" \
        "STATUS=Waiting" "CURRENT_PKG=-" "CURRENT_PCT=0" "OVERALL_PCT=0" \
        "COMPLETED=0" "TOTAL=$total" "FAILED_COUNT=0"

    if (( total == 0 )); then
        cache::set_many "$state_dir" "flatpak" "STATUS=Finished" "OVERALL_PCT=100"
        logger::info "FLATPAK" "-" "-" "No pending Flatpak updates"
        return 0
    fi

    logger::info "FLATPAK" "-" "-" "Starting update of $total Flatpak(s)"

    local start_epoch
    start_epoch="$(util::now_epoch)"

    local fifo
    fifo="$(mktemp -u "${state_dir}/flatpak_stream.XXXXXX")"
    mkfifo "$fifo"

    # --noninteractive avoids prompts; flatpak's own progress bar uses \r
    # redraws, so we translate those into line breaks first with a small
    # sed filter, then parse each resulting line.
    ( flatpak update -y --noninteractive 2>&1 | sed -u 's/\r/\n/g' > "$fifo"; echo "__FP_EXIT_$?__" >> "$fifo" ) &

    local current_pkg="-"
    local cur_state="Waiting"
    declare -A counted_pkgs=()

    exec 7< "$fifo"
    while IFS= read -r -u 7 line; do
        [[ "$line" =~ ^__FP_EXIT_[0-9]+__$ ]] && continue
        [[ -z "$line" ]] && continue

        # Lines like: "Installing:   org.gimp.GIMP/x86_64/stable   45%"
        if [[ "$line" =~ ^(Installing|Updating|Downloading)[[:space:]:]+([A-Za-z0-9._-]+) ]]; then
            current_pkg="${BASH_REMATCH[2]}"
        fi

        if [[ "$line" =~ ([0-9]{1,3})% ]]; then
            local pct="${BASH_REMATCH[1]}"
            cache::set "$state_dir" "flatpak" "CURRENT_PCT" "$pct"
        fi

        local mapped
        mapped="$(flatpak::_map_state "$line")"
        if [[ -n "$mapped" ]]; then
            cur_state="$mapped"
            cache::set_many "$state_dir" "flatpak" "STATUS=$cur_state" "CURRENT_PKG=$current_pkg"
        fi

        if { [[ "$line" =~ ^Now\ at ]] || [[ "$line" =~ "Installation complete" ]]; } && \
           [[ -z "${counted_pkgs[$current_pkg]:-}" ]]; then
            counted_pkgs["$current_pkg"]=1
            (( completed++ ))
            local overall_pct
            overall_pct="$(util::percent "$completed" "$total")"
            cache::set_many "$state_dir" "flatpak" "COMPLETED=$completed" "OVERALL_PCT=$overall_pct" "CURRENT_PCT=100"
            cache::append_completed "$state_dir" "flatpak" "$current_pkg" "-"
            logger::success "FLATPAK" "$current_pkg" "-" "updated"
        fi

        if [[ "$line" =~ [Ee]rror ]]; then
            (( failed++ ))
            cache::append_failure "$state_dir" "flatpak" "$current_pkg" "$line" "0"
            cache::set "$state_dir" "flatpak" "FAILED_COUNT" "$failed"
            logger::error "FLATPAK" "$current_pkg" "-" "$line"
        fi

        local elapsed=$(( $(util::now_epoch) - start_epoch ))
        cache::set "$state_dir" "flatpak" "ELAPSED" "$elapsed"
    done
    exec 7<&-
    rm -f "$fifo"

    cache::set_many "$state_dir" "flatpak" "STATUS=Finished" "OVERALL_PCT=100"
    logger::info "FLATPAK" "-" "-" "Flatpak update pass complete ($failed failure(s))"
    return "$failed"
}

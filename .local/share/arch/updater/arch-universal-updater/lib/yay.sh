#!/usr/bin/env bash
# =============================================================================
# lib/yay.sh - Yay (AUR helper) detection, update checking, and execution
# =============================================================================
# AUR builds go through several stages (clone, fetch PKGBUILD, resolve deps,
# build, package, install, clean) that yay/makepkg report as free-form text
# rather than a numeric percentage, so this module tracks stage-based
# progress instead of byte-level progress.
# =============================================================================

[[ -n "${ARCH_UPDATER_YAY_LOADED:-}" ]] && return 0
ARCH_UPDATER_YAY_LOADED=1

YAY_STAGES=(Cloning "Downloading PKGBUILD" "Resolving Dependencies" Building Packaging Installing Cleaning)

# ---------------------------------------------------------------------------
# yay::available - returns 0 if yay is installed
# ---------------------------------------------------------------------------
yay::available() {
    util::require_cmd yay
}

# ---------------------------------------------------------------------------
# yay::check_updates - print pending AUR updates, one per line
# ---------------------------------------------------------------------------
yay::check_updates() {
    yay::available || return 1
    yay -Qua 2>/dev/null
}

# ---------------------------------------------------------------------------
# yay::update_count
# ---------------------------------------------------------------------------
yay::update_count() {
    yay::check_updates | grep -c . || true
}

# ---------------------------------------------------------------------------
# yay::_stage_index <line> - map a raw yay/makepkg output line to an index
# into YAY_STAGES, or -1 if the line doesn't indicate a stage transition.
# ---------------------------------------------------------------------------
yay::_stage_index() {
    local line="$1"
    case "$line" in
        *"Cloning"*|*"cloning"*)                                   echo 0 ;;
        *"PKGBUILD"*|*"fetching"*)                                 echo 1 ;;
        *"Resolving dependencies"*|*"checking dependencies"*)       echo 2 ;;
        *"==> Making package"*|*"Building"*|*"==> Starting build"*) echo 3 ;;
        *"==> Creating package"*|*"Packaging"*)                     echo 4 ;;
        *"installing "*|*"Installing"*|*"upgrading "*)              echo 5 ;;
        *"Cleaning"*|*"removing untracked"*)                        echo 6 ;;
        *) echo -1 ;;
    esac
}

# ---------------------------------------------------------------------------
# yay::run_updates <state_dir> - run yay -Sua for AUR packages, streaming
# stage-based progress into cache/state/yay.state.
# ---------------------------------------------------------------------------
yay::run_updates() {
    local state_dir="$1"

    if ! yay::available; then
        cache::set_many "$state_dir" "yay" "STATUS=Finished" "OVERALL_PCT=100" "TOTAL=0" "COMPLETED=0"
        logger::info "YAY" "-" "-" "yay not installed, skipping AUR updates"
        return 0
    fi

    local total completed=0 failed=0
    total="$(yay::update_count)"
    [[ -z "$total" ]] && total=0

    cache::set_many "$state_dir" "yay" \
        "STATUS=Waiting" "CURRENT_PKG=-" "STAGE=-" "STAGE_INDEX=0" \
        "OVERALL_PCT=0" "COMPLETED=0" "TOTAL=$total" "ELAPSED=0" "FAILED_COUNT=0"

    if (( total == 0 )); then
        cache::set_many "$state_dir" "yay" "STATUS=Finished" "OVERALL_PCT=100"
        logger::info "YAY" "-" "-" "No pending AUR updates"
        return 0
    fi

    logger::info "YAY" "-" "-" "Starting update of $total AUR package(s)"

    local start_epoch
    start_epoch="$(util::now_epoch)"

    local fifo
    fifo="$(mktemp -u "${state_dir}/yay_stream.XXXXXX")"
    mkfifo "$fifo"

    ( yay -Sua --noconfirm --removemake > "$fifo" 2>&1; echo "__YAY_EXIT_$?__" >> "$fifo" ) &

    local current_pkg="-"
    local n_stages=${#YAY_STAGES[@]}

    exec 8< "$fifo"
    while IFS= read -r -u 8 line; do
        [[ "$line" =~ ^__YAY_EXIT_[0-9]+__$ ]] && continue

        # yay prints "Building <pkgname>" and similar package-scoped lines;
        # try to keep the current package name up to date.
        if [[ "$line" =~ ^Building\ ([A-Za-z0-9._+@-]+) ]]; then
            current_pkg="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^cloning\ ([A-Za-z0-9._+@-]+) ]]; then
            current_pkg="${BASH_REMATCH[1]}"
        fi

        local idx
        idx="$(yay::_stage_index "$line")"
        if (( idx >= 0 )); then
            local stage_name="${YAY_STAGES[$idx]}"
            local overall_pct
            overall_pct="$(util::percent "$completed" "$total")"
            cache::set_many "$state_dir" "yay" \
                "STATUS=Building" "CURRENT_PKG=$current_pkg" "STAGE=$stage_name" \
                "STAGE_INDEX=$idx" "STAGE_TOTAL=$n_stages"

            if (( idx == 5 )); then
                (( completed++ ))
                overall_pct="$(util::percent "$completed" "$total")"
                cache::set_many "$state_dir" "yay" "COMPLETED=$completed" "OVERALL_PCT=$overall_pct"
                cache::append_completed "$state_dir" "yay" "$current_pkg" "-"
                logger::success "YAY" "$current_pkg" "-" "installed"
            fi
        fi

        if [[ "$line" =~ error|Error|failed|FAILED ]]; then
            (( failed++ ))
            cache::append_failure "$state_dir" "yay" "$current_pkg" "$line" "0"
            cache::set "$state_dir" "yay" "FAILED_COUNT" "$failed"
            logger::error "YAY" "$current_pkg" "-" "$line"
        fi

        local elapsed=$(( $(util::now_epoch) - start_epoch ))
        cache::set "$state_dir" "yay" "ELAPSED" "$elapsed"
    done
    exec 8<&-
    rm -f "$fifo"

    cache::set_many "$state_dir" "yay" "STATUS=Finished" "OVERALL_PCT=100"
    logger::info "YAY" "-" "-" "Yay update pass complete ($failed failure(s))"
    return "$failed"
}

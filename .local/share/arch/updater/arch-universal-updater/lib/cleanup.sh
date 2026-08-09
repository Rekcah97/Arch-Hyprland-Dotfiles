#!/usr/bin/env bash
# =============================================================================
# lib/cleanup.sh - Optional post-update cleanup stage
# =============================================================================

[[ -n "${ARCH_UPDATER_CLEANUP_LOADED:-}" ]] && return 0
ARCH_UPDATER_CLEANUP_LOADED=1

# ---------------------------------------------------------------------------
# cleanup::orphans - remove orphaned pacman packages, print bytes freed
# ---------------------------------------------------------------------------
cleanup::orphans() {
    util::require_cmd pacman || return 0
    local orphans
    orphans="$(pacman -Qtdq 2>/dev/null)"
    if [[ -z "$orphans" ]]; then
        logger::info "CLEANUP" "-" "-" "No orphan packages to remove"
        return 0
    fi

    logger::info "CLEANUP" "-" "-" "Removing orphan packages: $(echo "$orphans" | tr '\n' ' ')"
    local sudo_cmd="sudo"
    util::require_cmd sudo || sudo_cmd=""
    # shellcheck disable=SC2086
    $sudo_cmd pacman -Rns --noconfirm $orphans >/dev/null 2>&1
    logger::success "CLEANUP" "-" "-" "Orphan packages removed"
}

# ---------------------------------------------------------------------------
# cleanup::flatpak_unused - remove unused flatpak runtimes
# ---------------------------------------------------------------------------
cleanup::flatpak_unused() {
    util::require_cmd flatpak || return 0
    logger::info "CLEANUP" "-" "-" "Removing unused Flatpak runtimes"
    flatpak uninstall --unused -y >/dev/null 2>&1
    logger::success "CLEANUP" "-" "-" "Unused Flatpak runtimes removed"
}

# ---------------------------------------------------------------------------
# cleanup::paccache - trim the pacman package cache, keeping 2 versions
# ---------------------------------------------------------------------------
cleanup::paccache() {
    if util::require_cmd paccache; then
        local sudo_cmd="sudo"
        util::require_cmd sudo || sudo_cmd=""
        logger::info "CLEANUP" "-" "-" "Trimming pacman package cache"
        $sudo_cmd paccache -rk2 >/dev/null 2>&1
        logger::success "CLEANUP" "-" "-" "Package cache trimmed"
    else
        logger::warn "CLEANUP" "-" "-" "paccache not installed (pacman-contrib), skipping cache trim"
    fi
}

# ---------------------------------------------------------------------------
# cleanup::disk_usage_mb <path> - snapshot free space for before/after diffs
# ---------------------------------------------------------------------------
cleanup::disk_usage_mb() {
    network::free_disk_mb "${1:-/}"
}

# ---------------------------------------------------------------------------
# cleanup::run - orchestrate the full cleanup stage, returns freed MB
# ---------------------------------------------------------------------------
cleanup::run() {
    local before after freed
    before="$(cleanup::disk_usage_mb /)"

    [[ "${CLEANUP_ORPHANS:-true}" == "true" ]] && cleanup::orphans
    [[ "${CLEANUP_FLATPAK_UNUSED:-true}" == "true" ]] && cleanup::flatpak_unused
    [[ "${CLEANUP_PACCACHE:-true}" == "true" ]] && cleanup::paccache

    after="$(cleanup::disk_usage_mb /)"
    freed=$(( after - before ))
    (( freed < 0 )) && freed=0
    logger::info "CLEANUP" "-" "-" "Cleanup complete, approximately ${freed} MB freed"
    printf '%s' "$freed"
}

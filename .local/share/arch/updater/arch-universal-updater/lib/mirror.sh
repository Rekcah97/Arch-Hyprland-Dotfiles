#!/usr/bin/env bash
# =============================================================================
# lib/mirror.sh - Optional pacman mirrorlist refresh
# =============================================================================
# When MIRROR_REFRESH=true, uses reflector (if installed) to rank mirrors by
# speed before the main sync/upgrade begins. Falls back to a no-op with a
# logged warning if reflector isn't available, rather than failing the run.
# =============================================================================

[[ -n "${ARCH_UPDATER_MIRROR_LOADED:-}" ]] && return 0
ARCH_UPDATER_MIRROR_LOADED=1

# ---------------------------------------------------------------------------
# mirror::refresh - rank and write a fresh /etc/pacman.d/mirrorlist
# Requires root privileges; safe to call under sudo from the main script.
# ---------------------------------------------------------------------------
mirror::refresh() {
    if ! util::require_cmd reflector; then
        logger::warn "MIRROR" "-" "-" "reflector not installed, skipping mirror refresh"
        return 1
    fi

    logger::info "MIRROR" "-" "-" "Refreshing mirrorlist with reflector"
    if sudo reflector --latest 20 --protocol https --sort rate \
        --save /etc/pacman.d/mirrorlist >/dev/null 2>&1; then
        logger::success "MIRROR" "-" "-" "Mirrorlist refreshed successfully"
        return 0
    else
        logger::error "MIRROR" "-" "-" "Mirrorlist refresh failed"
        return 1
    fi
}

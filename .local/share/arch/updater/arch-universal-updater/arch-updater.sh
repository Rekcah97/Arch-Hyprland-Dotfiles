#!/usr/bin/env bash
# =============================================================================
# arch-updater.sh - Arch Universal Updater
# =============================================================================
# A terminal dashboard that updates everything installed via pacman, yay
# (AUR), and Flatpak from a single interface, similar in spirit to btop or
# lazygit but purpose-built for system updates.
#
# Usage:
#   ./arch-updater.sh              Run the interactive dashboard
#   ./arch-updater.sh --check      Only report how many updates are pending
#   ./arch-updater.sh --no-dashboard   Run updates with plain log output
#   ./arch-updater.sh --help       Show usage information
# =============================================================================

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Module loading - order matters: utils first, then anything else that
# depends on it. Every module guards against double-sourcing internally.
# ---------------------------------------------------------------------------
# shellcheck source=lib/utils.sh
source "$ROOT_DIR/lib/utils.sh"
util::ensure_locale
# shellcheck source=lib/parser.sh
source "$ROOT_DIR/lib/parser.sh"
# shellcheck source=lib/logger.sh
source "$ROOT_DIR/lib/logger.sh"
# shellcheck source=lib/cache.sh
source "$ROOT_DIR/lib/cache.sh"
# shellcheck source=lib/network.sh
source "$ROOT_DIR/lib/network.sh"
# shellcheck source=lib/notifier.sh
source "$ROOT_DIR/lib/notifier.sh"
# shellcheck source=lib/mirror.sh
source "$ROOT_DIR/lib/mirror.sh"
# shellcheck source=lib/retry.sh
source "$ROOT_DIR/lib/retry.sh"
# shellcheck source=lib/progress.sh
source "$ROOT_DIR/lib/progress.sh"
# shellcheck source=lib/statistics.sh
source "$ROOT_DIR/lib/statistics.sh"
# shellcheck source=lib/pacman.sh
source "$ROOT_DIR/lib/pacman.sh"
# shellcheck source=lib/yay.sh
source "$ROOT_DIR/lib/yay.sh"
# shellcheck source=lib/flatpak.sh
source "$ROOT_DIR/lib/flatpak.sh"
# shellcheck source=lib/cleanup.sh
source "$ROOT_DIR/lib/cleanup.sh"
# shellcheck source=lib/ui.sh
source "$ROOT_DIR/lib/ui.sh"
# shellcheck source=lib/dashboard.sh
source "$ROOT_DIR/lib/dashboard.sh"

# ---------------------------------------------------------------------------
# main::usage
# ---------------------------------------------------------------------------
main::usage() {
    cat <<'EOF'
Arch Universal Updater

Usage:
  ./arch-updater.sh                 Launch the interactive dashboard
  ./arch-updater.sh --check         Print pending update counts and exit
  ./arch-updater.sh --no-dashboard  Run updates with plain scrolling output
  ./arch-updater.sh --theme NAME    Force a theme for this run
  ./arch-updater.sh --help          Show this message

Configuration lives in config/config.conf. See README.md for details.
EOF
}

# ---------------------------------------------------------------------------
# main::preflight - connectivity, DNS, pacman lock, and disk space checks.
# Prints a checklist to stdout (plain text; this happens before the
# alternate-screen dashboard is entered).
# ---------------------------------------------------------------------------
main::preflight() {
    local ok=true

    printf 'Arch Universal Updater — startup checks\n'
    printf '%s\n' "$(ui::hr 44 '-' 2>/dev/null || printf -- '--------------------------------------------')"

    printf '  [ ] Internet connectivity... '
    if network::check_connectivity "$CONNECTIVITY_CHECK_HOST"; then
        printf '\r  [x] Internet connectivity      \n'
    else
        printf '\r  [!] Internet connectivity FAILED\n'
        ok=false
    fi

    printf '  [ ] DNS resolution... '
    if network::check_dns "$DNS_CHECK_HOST"; then
        printf '\r  [x] DNS resolution             \n'
    else
        printf '\r  [!] DNS resolution FAILED\n'
        ok=false
    fi

    printf '  [ ] Pacman lock check... '
    if network::check_pacman_lock; then
        printf '\r  [x] Pacman lock check           \n'
    else
        printf '\r  [!] Pacman database is locked (another pacman process running?)\n'
        ok=false
    fi

    printf '  [ ] Disk space (min %sMB)... ' "$MIN_FREE_DISK_MB"
    if network::check_disk_space "$MIN_FREE_DISK_MB"; then
        printf '\r  [x] Disk space (%sMB free)      \n' "$(network::free_disk_mb /)"
    else
        printf '\r  [!] Low disk space (%sMB free, need %sMB)\n' "$(network::free_disk_mb /)" "$MIN_FREE_DISK_MB"
        ok=false
    fi

    printf '  [ ] Detecting package managers... '
    local detected=()
    pacman::available  && detected+=("pacman")
    yay::available     && detected+=("yay")
    flatpak::available  && detected+=("flatpak")
    printf '\r  [x] Detected: %s\n' "${detected[*]:-none}"

    if [[ "$ok" != "true" ]]; then
        printf '\nOne or more preflight checks failed. '
        printf 'Continue anyway? [y/N] '
        read -r answer
        [[ "$answer" =~ ^[Yy]$ ]] || { printf 'Aborting.\n'; exit 1; }
    fi
}

# ---------------------------------------------------------------------------
# main::scan_updates - print a quick summary of pending update counts
# ---------------------------------------------------------------------------
main::scan_updates() {
    printf '\nScanning for updates...\n'
    local p=0 y=0 f=0
    pacman::available  && p="$(pacman::update_count)"
    yay::available     && y="$(yay::update_count)"
    flatpak::available  && f="$(flatpak::update_count)"
    printf '  Pacman:  %s update(s)\n' "${p:-0}"
    printf '  Yay:     %s update(s)\n' "${y:-0}"
    printf '  Flatpak: %s update(s)\n' "${f:-0}"
    printf '  Total:   %s update(s)\n\n' "$(( ${p:-0} + ${y:-0} + ${f:-0} ))"
}

# ---------------------------------------------------------------------------
# main::run - full interactive flow
# ---------------------------------------------------------------------------
main::run() {
    local theme_override=""
    local mode="dashboard"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check)         mode="check" ;;
            --no-dashboard)  mode="plain" ;;
            --theme)         theme_override="${2:-}"; shift ;;
            --help|-h)       main::usage; exit 0 ;;
            *)               printf 'Unknown option: %s\n' "$1"; main::usage; exit 1 ;;
        esac
        shift
    done

    parser::load_config "$ROOT_DIR"
    parser::load_keybindings "$ROOT_DIR"
    [[ -n "$theme_override" ]] && THEME="$theme_override"
    parser::load_theme "$ROOT_DIR" "$THEME"

    util::mkdir_safe "$LOG_DIR"
    util::mkdir_safe "$CACHE_DIR"
    util::mkdir_safe "$STATE_DIR"

    logger::init "$LOG_DIR" "$LOG_FILE" "$LOG_ARCHIVE_COUNT"
    cache::init "$STATE_DIR"

    main::preflight

    if [[ "$mode" == "check" ]]; then
        main::scan_updates
        exit 0
    fi

    main::scan_updates

    [[ "${MIRROR_REFRESH:-false}" == "true" ]] && mirror::refresh

    if [[ "$mode" == "plain" ]]; then
        printf 'Running updates without the dashboard (plain mode)...\n\n'
        [[ "${ENABLE_PACMAN:-true}" == "true" ]] && pacman::run_updates "$STATE_DIR"
        [[ "${ENABLE_YAY:-true}" == "true" ]] && yay::run_updates "$STATE_DIR"
        [[ "${ENABLE_FLATPAK:-true}" == "true" ]] && flatpak::run_updates "$STATE_DIR"
        [[ "${CLEANUP_ENABLED:-false}" == "true" ]] && cleanup::run
        local failed
        failed="$(cache::failure_count "$STATE_DIR")"
        printf '\nDone. %s failure(s). Log: %s\n' "$failed" "$(logger::path)"
        exit 0
    fi

    printf 'Launching dashboard...\n'
    sleep 0.4
    dashboard::run "$ROOT_DIR"

    printf '\n\nSession finished. Log saved to: %s\n' "$(logger::path)"
}

main::run "$@"

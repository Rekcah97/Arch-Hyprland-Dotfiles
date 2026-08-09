#!/usr/bin/env bash
# =============================================================================
# lib/parser.sh - Configuration, theme, and keybinding loader
# =============================================================================
# Responsible for reading config/config.conf, config/colors.conf,
# config/keybindings.conf, and the active theme file, exposing everything as
# plain shell variables that the rest of the application reads.
# =============================================================================

[[ -n "${ARCH_UPDATER_PARSER_LOADED:-}" ]] && return 0
ARCH_UPDATER_PARSER_LOADED=1

# ---------------------------------------------------------------------------
# parser::load_config - source config/config.conf, falling back to safe
# defaults for anything missing so the app never crashes on a stripped-down
# config file.
# ---------------------------------------------------------------------------
parser::load_config() {
    local root="$1"
    local conf="$root/config/config.conf"

    # Defaults first, so a partial/edited config.conf can't leave a variable
    # unset.
    THEME="default"
    REFRESH_RATE=0.25
    COMPACT_MODE="false"
    ENABLE_PACMAN="true"
    ENABLE_YAY="true"
    ENABLE_FLATPAK="true"
    AUTO_RETRY="true"
    RETRY_COUNT=3
    RETRY_DELAY=3
    MIRROR_REFRESH="false"
    CLEANUP_ENABLED="false"
    CLEANUP_ORPHANS="true"
    CLEANUP_FLATPAK_UNUSED="true"
    CLEANUP_PACCACHE="true"
    NOTIFICATIONS_ENABLED="true"
    NOTIFY_ON_FINISH="true"
    NOTIFY_ON_FAILURE="true"
    NOTIFY_ON_RETRY_COMPLETE="true"
    NOTIFY_ON_CLEANUP="true"
    LOG_DIR="logs"
    LOG_FILE="latest.log"
    LOG_ARCHIVE_COUNT=10
    CONNECTIVITY_CHECK_HOST="archlinux.org"
    DNS_CHECK_HOST="one.one.one.one"
    MIN_FREE_DISK_MB=1024
    CACHE_DIR="cache"
    STATE_DIR="cache/state"

    if [[ -f "$conf" ]]; then
        # shellcheck disable=SC1090
        source "$conf"
    fi

    # Normalize to absolute paths.
    LOG_DIR="$root/$LOG_DIR"
    CACHE_DIR="$root/$CACHE_DIR"
    STATE_DIR="$root/$STATE_DIR"

    export THEME REFRESH_RATE COMPACT_MODE ENABLE_PACMAN ENABLE_YAY ENABLE_FLATPAK
    export AUTO_RETRY RETRY_COUNT RETRY_DELAY MIRROR_REFRESH
    export CLEANUP_ENABLED CLEANUP_ORPHANS CLEANUP_FLATPAK_UNUSED CLEANUP_PACCACHE
    export NOTIFICATIONS_ENABLED NOTIFY_ON_FINISH NOTIFY_ON_FAILURE
    export NOTIFY_ON_RETRY_COMPLETE NOTIFY_ON_CLEANUP
    export LOG_DIR LOG_FILE LOG_ARCHIVE_COUNT
    export CONNECTIVITY_CHECK_HOST DNS_CHECK_HOST MIN_FREE_DISK_MB
    export CACHE_DIR STATE_DIR
}

# ---------------------------------------------------------------------------
# parser::load_keybindings - source config/keybindings.conf with defaults
# ---------------------------------------------------------------------------
parser::load_keybindings() {
    local root="$1"
    local conf="$root/config/keybindings.conf"

    KEY_QUIT="q"
    KEY_LOG_TOGGLE="l"
    KEY_PAUSE="p"
    KEY_RETRY_FAILED="r"
    KEY_CLEANUP_TOGGLE="c"
    KEY_SUMMARY="s"
    KEY_DOWNLOAD_STATS="d"
    KEY_THEME_SWITCH="t"
    KEY_COMPACT_TOGGLE="f"
    KEY_EXPORT="e"
    KEY_HELP="h"
    KEY_HELP_ALT="?"

    if [[ -f "$conf" ]]; then
        # shellcheck disable=SC1090
        source "$conf"
    fi

    export KEY_QUIT KEY_LOG_TOGGLE KEY_PAUSE KEY_RETRY_FAILED KEY_CLEANUP_TOGGLE
    export KEY_SUMMARY KEY_DOWNLOAD_STATS KEY_THEME_SWITCH KEY_COMPACT_TOGGLE
    export KEY_EXPORT KEY_HELP KEY_HELP_ALT
}

# ---------------------------------------------------------------------------
# parser::load_theme <root> <theme_name> - source themes/<name>.theme and
# apply any user overrides from config/colors.conf on top.
# ---------------------------------------------------------------------------
parser::load_theme() {
    local root="$1"
    local name="${2:-default}"
    local theme_file="$root/themes/${name}.theme"

    if [[ ! -f "$theme_file" ]]; then
        theme_file="$root/themes/default.theme"
    fi

    # shellcheck disable=SC1090
    source "$theme_file"

    local overrides="$root/config/colors.conf"
    if [[ -f "$overrides" ]]; then
        # shellcheck disable=SC1090
        source "$overrides"
        [[ -n "${OVERRIDE_ACCENT:-}" ]] && COLOR_ACCENT="$OVERRIDE_ACCENT"
        [[ -n "${OVERRIDE_SUCCESS:-}" ]] && COLOR_SUCCESS="$OVERRIDE_SUCCESS"
        [[ -n "${OVERRIDE_WARNING:-}" ]] && COLOR_WARNING="$OVERRIDE_WARNING"
        [[ -n "${OVERRIDE_ERROR:-}" ]] && COLOR_ERROR="$OVERRIDE_ERROR"
        [[ -n "${OVERRIDE_TEXT:-}" ]] && COLOR_TEXT="$OVERRIDE_TEXT"
        [[ -n "${OVERRIDE_BORDER:-}" ]] && COLOR_BORDER="$OVERRIDE_BORDER"
    fi

    export COLOR_ACCENT COLOR_SUCCESS COLOR_WARNING COLOR_ERROR COLOR_TEXT
    export COLOR_BORDER COLOR_BG COLOR_MUTED COLOR_PACMAN COLOR_YAY COLOR_FLATPAK
}

# ---------------------------------------------------------------------------
# parser::next_theme <current> - return the name of the next theme in the
# rotation, used by the "T" (switch theme) shortcut.
# ---------------------------------------------------------------------------
parser::next_theme() {
    local current="$1"
    local themes=(default nord catppuccin dark)
    local i
    for i in "${!themes[@]}"; do
        if [[ "${themes[$i]}" == "$current" ]]; then
            local next=$(( (i + 1) % ${#themes[@]} ))
            echo "${themes[$next]}"
            return
        fi
    done
    echo "default"
}

#!/usr/bin/env bash
# =============================================================================
# lib/progress.sh - Progress bar rendering
# =============================================================================
# Renders Unicode block progress bars like:  ████████████░░░░░░░░░░░
# Used for both "overall" and "per-package" progress in every manager panel.
# =============================================================================

[[ -n "${ARCH_UPDATER_PROGRESS_LOADED:-}" ]] && return 0
ARCH_UPDATER_PROGRESS_LOADED=1

# ---------------------------------------------------------------------------
# progress::bar <percent 0-100> <width> <color_code> - print a colored bar
# ---------------------------------------------------------------------------
progress::bar() {
    local pct="${1:-0}" width="${2:-24}" color="${3:-$COLOR_ACCENT}"

    # Clamp percent into [0,100]
    (( pct < 0 )) && pct=0
    (( pct > 100 )) && pct=100

    local filled=$(( (pct * width) / 100 ))
    local empty=$(( width - filled ))

    local fill_glyph="█" empty_glyph="░"
    [[ "${ARCH_UPDATER_ASCII_MODE:-0}" == "1" ]] && { fill_glyph="#"; empty_glyph="."; }

    local filled_str="" empty_str=""
    (( filled > 0 )) && filled_str="$(printf "${fill_glyph}%.0s" $(seq 1 "$filled"))"
    (( empty > 0 )) && empty_str="$(printf "${empty_glyph}%.0s" $(seq 1 "$empty"))"

    printf '\e[38;5;%sm%s\e[38;5;%sm%s\e[0m' "$color" "$filled_str" "${COLOR_MUTED}" "$empty_str"
}

# ---------------------------------------------------------------------------
# progress::bar_with_label <percent> <width> <color> - bar followed by " NN%"
# ---------------------------------------------------------------------------
progress::bar_with_label() {
    local pct="${1:-0}" width="${2:-24}" color="${3:-$COLOR_ACCENT}"
    local bar
    bar="$(progress::bar "$pct" "$width" "$color")"
    printf '%s \e[38;5;%sm%3d%%\e[0m' "$bar" "$COLOR_TEXT" "$pct"
}

# ---------------------------------------------------------------------------
# progress::stage_bar <stage_index> <total_stages> <width> <color> - a
# stage-based bar for managers that don't expose byte-level progress (yay
# builds, flatpak deploys). Fills proportionally to how many stages are done.
# ---------------------------------------------------------------------------
progress::stage_bar() {
    local idx="${1:-0}" total="${2:-1}" width="${3:-24}" color="${4:-$COLOR_ACCENT}"
    (( total <= 0 )) && total=1
    local pct=$(( (idx * 100) / total ))
    progress::bar_with_label "$pct" "$width" "$color"
}

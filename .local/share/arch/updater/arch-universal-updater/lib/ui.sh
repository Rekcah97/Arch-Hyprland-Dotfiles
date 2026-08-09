#!/usr/bin/env bash
# =============================================================================
# lib/ui.sh - Low-level terminal UI primitives
# =============================================================================
# Cursor control, ANSI color helpers, Unicode box-drawing, and non-blocking
# keyboard input. lib/dashboard.sh builds the actual panels on top of these
# primitives; this file has no knowledge of update logic or panel layout.
# =============================================================================

[[ -n "${ARCH_UPDATER_UI_LOADED:-}" ]] && return 0
ARCH_UPDATER_UI_LOADED=1

UI_TERM_ROWS=24
UI_TERM_COLS=80

# ---------------------------------------------------------------------------
# ui::init - enter the fullscreen alternate buffer, hide the cursor
# ---------------------------------------------------------------------------
ui::init() {
    tput smcup 2>/dev/null            # switch to alternate screen buffer
    tput civis 2>/dev/null            # hide cursor
    stty -echo -icanon time 0 min 0 2>/dev/null
    ui::update_dimensions
    clear
}

# ---------------------------------------------------------------------------
# ui::restore - leave the alternate buffer and restore terminal settings
# ---------------------------------------------------------------------------
ui::restore() {
    stty sane 2>/dev/null
    tput cnorm 2>/dev/null            # show cursor
    tput rmcup 2>/dev/null            # leave alternate screen buffer
}

# ---------------------------------------------------------------------------
# ui::update_dimensions - refresh cached terminal size
# ---------------------------------------------------------------------------
ui::update_dimensions() {
    UI_TERM_ROWS="$(tput lines 2>/dev/null || echo 24)"
    UI_TERM_COLS="$(tput cols 2>/dev/null || echo 80)"
}

# ---------------------------------------------------------------------------
# ui::goto <row> <col> - move cursor (1-indexed)
# ---------------------------------------------------------------------------
ui::goto() {
    printf '\e[%d;%dH' "$1" "$2"
}

# ---------------------------------------------------------------------------
# ui::clear_line - clear from cursor to end of line
# ---------------------------------------------------------------------------
ui::clear_line() {
    printf '\e[K'
}

# ---------------------------------------------------------------------------
# ui::color_fg <code> <text> - wrap text in a 256-color foreground escape
# ---------------------------------------------------------------------------
ui::color_fg() {
    printf '\e[38;5;%sm%s\e[0m' "$1" "$2"
}

# ---------------------------------------------------------------------------
# ui::bold <text>
# ---------------------------------------------------------------------------
ui::bold() {
    printf '\e[1m%s\e[0m' "$1"
}

# ---------------------------------------------------------------------------
# ui::dim <text>
# ---------------------------------------------------------------------------
ui::dim() {
    printf '\e[2m%s\e[0m' "$1"
}

# ---------------------------------------------------------------------------
# ui::hr <width> <char> - horizontal rule using a box-drawing character
# ---------------------------------------------------------------------------
ui::hr() {
    local width="${1:-40}" ch="${2:-─}"
    printf '%s' "$(printf "${ch}%.0s" $(seq 1 "$width"))"
}

# ---------------------------------------------------------------------------
# ui::box_top / box_bottom / box_side - draw a bordered panel using
# rounded Unicode box-drawing characters.
# ---------------------------------------------------------------------------
ui::box_top() {
    local width="$1" title="${2:-}" color="${3:-$COLOR_BORDER}"
    local tl="╭" hbar="─" tr="╮"
    if [[ "${ARCH_UPDATER_ASCII_MODE:-0}" == "1" ]]; then
        tl="+"; hbar="-"; tr="+"
    fi
    local line="$tl"
    if [[ -n "$title" ]]; then
        local label=" ${title} "
        local remaining=$(( width - ${#label} - 2 ))
        (( remaining < 0 )) && remaining=0
        line+="${hbar}${label}$(ui::hr "$remaining" "$hbar")"
    else
        line+="$(ui::hr $(( width - 2 )) "$hbar")"
    fi
    line+="$tr"
    ui::color_fg "$color" "$line"
    printf '\n'
}

ui::box_bottom() {
    local width="$1" color="${2:-$COLOR_BORDER}"
    local bl="╰" hbar="─" br="╯"
    if [[ "${ARCH_UPDATER_ASCII_MODE:-0}" == "1" ]]; then
        bl="+"; hbar="-"; br="+"
    fi
    local line="${bl}$(ui::hr $(( width - 2 )) "$hbar")${br}"
    ui::color_fg "$color" "$line"
    printf '\n'
}

ui::box_line() {
    local width="$1" content="$2" color="${3:-$COLOR_BORDER}"
    local side="│"
    [[ "${ARCH_UPDATER_ASCII_MODE:-0}" == "1" ]] && side="|"
    local inner=$(( width - 2 ))
    local visible
    visible="$(ui::strip_ansi "$content")"
    # bash's ${#string} is character-aware (not byte-aware) as long as a
    # UTF-8 locale is active, which util::ensure_locale guarantees at
    # startup. This is more reliable across systems than shelling out to
    # awk, whose multibyte support varies by implementation (mawk vs gawk).
    local vlen=${#visible}
    local pad=$(( inner - vlen - 2 ))
    (( pad < 0 )) && pad=0
    printf '%s %s%*s%s\n' "$(ui::color_fg "$color" "$side")" "$content" "$pad" "" "$(ui::color_fg "$color" "$side")"
}

# ---------------------------------------------------------------------------
# ui::strip_ansi <string> - remove ANSI escape sequences (for width math)
# ---------------------------------------------------------------------------
ui::strip_ansi() {
    printf '%s' "$1" | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g'
}

# ---------------------------------------------------------------------------
# ui::read_key - waits briefly for a single keypress, returning "" if none
# arrived in that window.
#
# NOTE: an earlier version of this function used `read -t 0` to test for
# available input before consuming it with a second read. That relies on
# `read -t 0` never consuming a byte on its own, which turned out to behave
# inconsistently across invocations in practice (occasionally swallowing
# the keypress and leaving nothing for the follow-up read, so shortcuts
# would intermittently not register). A single `read` with a small nonzero
# timeout is unambiguous: it waits up to that long for a byte and consumes
# it if one shows up, otherwise returns empty. The dashboard's render loop
# already sleeps between iterations, so this timeout simply folds into
# that existing cadence rather than adding extra latency.
# ---------------------------------------------------------------------------
ui::read_key() {
    local key=""
    IFS= read -r -s -n 1 -t 0.05 key 2>/dev/null
    printf '%s' "$key"
}

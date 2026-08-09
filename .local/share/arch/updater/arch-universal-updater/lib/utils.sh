#!/usr/bin/env bash
# =============================================================================
# lib/utils.sh - Shared helper functions
# =============================================================================
# Provides generic utilities used by every other module: path resolution,
# safe sourcing, string padding, human-readable byte formatting, time
# formatting, and small math helpers used by the progress bar renderer.
# =============================================================================

# Guard against double-sourcing
[[ -n "${ARCH_UPDATER_UTILS_LOADED:-}" ]] && return 0
ARCH_UPDATER_UTILS_LOADED=1

# ---------------------------------------------------------------------------
# util::root - print the absolute path of the project root
# ---------------------------------------------------------------------------
util::root() {
    local src="${BASH_SOURCE[0]}"
    cd "$(dirname "$src")/.." && pwd
}

# ---------------------------------------------------------------------------
# util::require_cmd <cmd> - return 0 if a command exists on PATH
# ---------------------------------------------------------------------------
util::require_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# util::pad_right <string> <width> - pad a string with spaces on the right
# ---------------------------------------------------------------------------
util::pad_right() {
    local str="$1" width="$2"
    local len=${#str}
    if (( len >= width )); then
        printf '%s' "${str:0:width}"
    else
        printf '%s%*s' "$str" $((width - len)) ""
    fi
}

# ---------------------------------------------------------------------------
# util::pad_left <string> <width> - pad a string with spaces on the left
# ---------------------------------------------------------------------------
util::pad_left() {
    local str="$1" width="$2"
    printf '%*s' "$width" "$str"
}

# ---------------------------------------------------------------------------
# util::human_bytes <bytes> - convert raw byte count to human-readable form
# ---------------------------------------------------------------------------
util::human_bytes() {
    local bytes="${1:-0}"
    local units=(B KiB MiB GiB TiB)
    local i=0
    local value="$bytes"

    # Use awk for floating point since bash only does integers
    awk -v b="$bytes" 'BEGIN {
        split("B KiB MiB GiB TiB", units, " ")
        u = 1
        v = b
        while (v >= 1024 && u < 5) {
            v /= 1024
            u++
        }
        printf "%.1f %s", v, units[u]
    }'
}

# ---------------------------------------------------------------------------
# util::human_time <seconds> - format seconds as HH:MM:SS
# ---------------------------------------------------------------------------
util::human_time() {
    local total="${1:-0}"
    total=${total%.*}
    [[ -z "$total" || "$total" == "-" ]] && total=0
    local h=$(( total / 3600 ))
    local m=$(( (total % 3600) / 60 ))
    local s=$(( total % 60 ))
    printf '%02d:%02d:%02d' "$h" "$m" "$s"
}

# ---------------------------------------------------------------------------
# util::now_epoch - current unix timestamp
# ---------------------------------------------------------------------------
util::now_epoch() {
    date +%s
}

# ---------------------------------------------------------------------------
# util::now_iso - current ISO-8601 timestamp for logs
# ---------------------------------------------------------------------------
util::now_iso() {
    date '+%Y-%m-%d %H:%M:%S'
}

# ---------------------------------------------------------------------------
# util::clamp <value> <min> <max>
# ---------------------------------------------------------------------------
util::clamp() {
    local v="$1" min="$2" max="$3"
    awk -v v="$v" -v mn="$min" -v mx="$max" 'BEGIN {
        if (v < mn) v = mn
        if (v > mx) v = mx
        printf "%.4f", v
    }'
}

# ---------------------------------------------------------------------------
# util::percent <numerator> <denominator> - safe integer percentage
# ---------------------------------------------------------------------------
util::percent() {
    local num="${1:-0}" den="${2:-0}"
    if [[ -z "$den" || "$den" == "0" ]]; then
        echo 0
        return
    fi
    awk -v n="$num" -v d="$den" 'BEGIN { printf "%d", (n / d) * 100 }'
}

# ---------------------------------------------------------------------------
# util::mkdir_safe <dir> - create a directory tree, ignoring failures loudly
# ---------------------------------------------------------------------------
util::mkdir_safe() {
    mkdir -p "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# util::atomic_write <file> <content> - write content to a file atomically
# ---------------------------------------------------------------------------
util::atomic_write() {
    local file="$1" content="$2"
    local tmp
    tmp="$(mktemp "${file}.XXXXXX")"
    printf '%s' "$content" > "$tmp"
    mv -f "$tmp" "$file"
}

# ---------------------------------------------------------------------------
# util::trim <string> - strip leading/trailing whitespace
# ---------------------------------------------------------------------------
util::trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# util::ensure_locale - Unicode box-drawing/progress glyphs are multi-byte
# in UTF-8, and bash's ${#string} only counts them as one character per
# glyph when running under a UTF-8-aware locale. Under the "C" locale it
# counts raw bytes instead, which silently breaks all width math used by
# ui::box_line and the progress bars. To keep rendering correct everywhere,
# try to force a UTF-8 locale; if none is installed, fall back to an ASCII
# rendering mode (ARCH_UPDATER_ASCII_MODE=1) that lib/ui.sh and
# lib/progress.sh check before choosing which glyph set to draw.
# ---------------------------------------------------------------------------
util::ensure_locale() {
    ARCH_UPDATER_ASCII_MODE=0

    if [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" == *UTF-8* || "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" == *utf8* ]]; then
        return 0
    fi

    local candidate
    for candidate in en_US.UTF-8 C.UTF-8; do
        if command -v locale >/dev/null 2>&1 && locale -a 2>/dev/null | grep -qi "^${candidate//-/}$\|^${candidate}$"; then
            export LC_ALL="$candidate"
            return 0
        fi
    done

    # No UTF-8 locale available: fall back to ASCII-safe glyphs rather than
    # risk garbled/misaligned panels.
    ARCH_UPDATER_ASCII_MODE=1
}
export ARCH_UPDATER_ASCII_MODE="${ARCH_UPDATER_ASCII_MODE:-0}"

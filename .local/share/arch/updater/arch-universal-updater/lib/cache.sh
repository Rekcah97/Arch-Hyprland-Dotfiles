#!/usr/bin/env bash
# =============================================================================
# lib/cache.sh - Runtime state store
# =============================================================================
# The dashboard and the package-manager workers run as separate processes.
# To communicate live progress, each worker periodically writes simple
# key=value "state files" under cache/state/, and the dashboard polls and
# renders them. This keeps the UI decoupled from update logic, per the
# project's architecture requirements.
# =============================================================================

[[ -n "${ARCH_UPDATER_CACHE_LOADED:-}" ]] && return 0
ARCH_UPDATER_CACHE_LOADED=1

# ---------------------------------------------------------------------------
# cache::init <state_dir> - prepare the state directory for a fresh run
# ---------------------------------------------------------------------------
cache::init() {
    local dir="$1"
    util::mkdir_safe "$dir"
    rm -f "$dir"/*.state "$dir"/*.log 2>/dev/null
    : > "$dir/failures.log"
    : > "$dir/completed.log"
    : > "$dir/control.flags"
}

# ---------------------------------------------------------------------------
# cache::set <state_dir> <manager> <key> <value> - update a single field in
# a manager's state file (rewrites the whole file; state files are small).
# ---------------------------------------------------------------------------
cache::set() {
    local dir="$1" mgr="$2" key="$3" val="$4"
    local file="$dir/${mgr}.state"
    local tmp
    tmp="$(mktemp "${file}.XXXXXX" 2>/dev/null)" || tmp="${file}.tmp"

    if [[ -f "$file" ]]; then
        grep -v "^${key}=" "$file" > "$tmp" 2>/dev/null
    else
        : > "$tmp"
    fi
    printf '%s=%s\n' "$key" "$val" >> "$tmp"
    mv -f "$tmp" "$file"
}

# ---------------------------------------------------------------------------
# cache::set_many <state_dir> <manager> <key=value> [<key=value> ...] - batch
# update, avoids repeated file rewrites when several fields change together.
# ---------------------------------------------------------------------------
cache::set_many() {
    local dir="$1" mgr="$2"; shift 2
    local file="$dir/${mgr}.state"
    declare -A merged=()

    if [[ -f "$file" ]]; then
        while IFS='=' read -r k v; do
            [[ -z "$k" ]] && continue
            merged["$k"]="$v"
        done < "$file"
    fi

    local pair k v
    for pair in "$@"; do
        k="${pair%%=*}"
        v="${pair#*=}"
        merged["$k"]="$v"
    done

    local tmp
    tmp="$(mktemp "${file}.XXXXXX" 2>/dev/null)" || tmp="${file}.tmp"
    : > "$tmp"
    for k in "${!merged[@]}"; do
        printf '%s=%s\n' "$k" "${merged[$k]}" >> "$tmp"
    done
    mv -f "$tmp" "$file"
}

# ---------------------------------------------------------------------------
# cache::get <state_dir> <manager> <key> [default] - read one field
# ---------------------------------------------------------------------------
cache::get() {
    local dir="$1" mgr="$2" key="$3" default="${4:-}"
    local file="$dir/${mgr}.state"
    local line
    [[ -f "$file" ]] || { printf '%s' "$default"; return; }
    line="$(grep "^${key}=" "$file" 2>/dev/null | tail -n1)"
    if [[ -z "$line" ]]; then
        printf '%s' "$default"
    else
        printf '%s' "${line#*=}"
    fi
}

# ---------------------------------------------------------------------------
# cache::append_completed <state_dir> <manager> <package> <version> - record
# a successfully updated package, keeping only the most recent entries the
# dashboard needs to show the "last 5 completed" panel across all managers.
# ---------------------------------------------------------------------------
cache::append_completed() {
    local dir="$1" mgr="$2" pkg="$3" ver="${4:--}"
    printf '%s|%s|%s|%s\n' "$(util::now_iso)" "$mgr" "$pkg" "$ver" >> "$dir/completed.log"
}

# ---------------------------------------------------------------------------
# cache::recent_completed <state_dir> <n> - print the n most recent
# completed packages across all managers, most recent first.
# ---------------------------------------------------------------------------
cache::recent_completed() {
    local dir="$1" n="${2:-5}"
    [[ -f "$dir/completed.log" ]] && tail -n "$n" "$dir/completed.log" | tac
}

# ---------------------------------------------------------------------------
# cache::append_failure <state_dir> <manager> <package> <reason> <retries>
# ---------------------------------------------------------------------------
cache::append_failure() {
    local dir="$1" mgr="$2" pkg="$3" reason="$4" retries="${5:-0}"
    printf '%s|%s|%s|%s|%s\n' "$(util::now_iso)" "$mgr" "$pkg" "$reason" "$retries" >> "$dir/failures.log"
}

# ---------------------------------------------------------------------------
# cache::failure_count <state_dir>
# ---------------------------------------------------------------------------
cache::failure_count() {
    local dir="$1"
    [[ -f "$dir/failures.log" ]] && wc -l < "$dir/failures.log" || echo 0
}

# ---------------------------------------------------------------------------
# cache::all_failures <state_dir>
# ---------------------------------------------------------------------------
cache::all_failures() {
    local dir="$1"
    [[ -f "$dir/failures.log" ]] && cat "$dir/failures.log"
}

# ---------------------------------------------------------------------------
# cache::set_flag / get_flag - control flags shared between the dashboard's
# keyboard handler and the worker processes (pause, quit, cleanup toggle).
# ---------------------------------------------------------------------------
cache::set_flag() {
    local dir="$1" flag="$2" val="$3"
    cache::set "$dir" "control" "$flag" "$val"
    # control.flags mirror kept for quick greps by workers that poll rapidly
    grep -v "^${flag}=" "$dir/control.flags" 2>/dev/null > "$dir/control.flags.tmp" || true
    printf '%s=%s\n' "$flag" "$val" >> "$dir/control.flags.tmp"
    mv -f "$dir/control.flags.tmp" "$dir/control.flags"
}

cache::get_flag() {
    local dir="$1" flag="$2" default="${3:-false}"
    cache::get "$dir" "control" "$flag" "$default"
}

#!/usr/bin/env bash
# =============================================================================
# lib/network.sh - Connectivity, DNS, and disk-space preflight checks
# =============================================================================

[[ -n "${ARCH_UPDATER_NETWORK_LOADED:-}" ]] && return 0
ARCH_UPDATER_NETWORK_LOADED=1

# ---------------------------------------------------------------------------
# network::check_connectivity <host> - returns 0 if the host is reachable
# ---------------------------------------------------------------------------
network::check_connectivity() {
    local host="${1:-archlinux.org}"
    if util::require_cmd ping; then
        ping -c 1 -W 2 "$host" >/dev/null 2>&1 && return 0
    fi
    if util::require_cmd curl; then
        curl -s --max-time 3 --head "https://$host" >/dev/null 2>&1 && return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# network::check_dns <host> - returns 0 if DNS resolution succeeds
# ---------------------------------------------------------------------------
network::check_dns() {
    local host="${1:-one.one.one.one}"
    if util::require_cmd getent; then
        getent hosts "$host" >/dev/null 2>&1 && return 0
    fi
    if util::require_cmd nslookup; then
        nslookup "$host" >/dev/null 2>&1 && return 0
    fi
    # Fall back to /dev/tcp against a well-known resolver port.
    (exec 3<>"/dev/tcp/$host/443") >/dev/null 2>&1 && { exec 3>&- 3<&-; return 0; }
    return 1
}

# ---------------------------------------------------------------------------
# network::check_pacman_lock - returns 0 if no pacman DB lock is held
# ---------------------------------------------------------------------------
network::check_pacman_lock() {
    [[ ! -f /var/lib/pacman/db.lck ]]
}

# ---------------------------------------------------------------------------
# network::free_disk_mb <path> - print free space in MB for the given path
# ---------------------------------------------------------------------------
network::free_disk_mb() {
    local path="${1:-/}"
    df -Pm "$path" 2>/dev/null | awk 'NR==2 {print $4}'
}

# ---------------------------------------------------------------------------
# network::check_disk_space <min_mb> - returns 0 if enough free space exists
# ---------------------------------------------------------------------------
network::check_disk_space() {
    local min_mb="${1:-1024}"
    local free
    free="$(network::free_disk_mb /)"
    [[ -n "$free" ]] && (( free >= min_mb ))
}

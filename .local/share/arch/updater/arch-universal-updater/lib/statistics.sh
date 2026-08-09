#!/usr/bin/env bash
# =============================================================================
# lib/statistics.sh - System statistics for the dashboard's info panel
# =============================================================================
# All functions are cheap, best-effort, and never fail the caller; if a stat
# can't be determined, a placeholder ("--") is printed instead.
# =============================================================================

[[ -n "${ARCH_UPDATER_STATISTICS_LOADED:-}" ]] && return 0
ARCH_UPDATER_STATISTICS_LOADED=1

STATS_PREV_RX=0
STATS_PREV_TX=0
STATS_PREV_TS=0

# ---------------------------------------------------------------------------
# statistics::cpu_usage - approximate overall CPU usage percentage, sampled
# via /proc/stat over a very short window (non-blocking, ~50ms).
# ---------------------------------------------------------------------------
statistics::cpu_usage() {
    [[ -r /proc/stat ]] || { echo "--"; return; }

    local a b
    a="$(head -n1 /proc/stat)"
    sleep 0.05
    b="$(head -n1 /proc/stat)"

    awk -v a="$a" -v b="$b" 'BEGIN {
        split(a, A, " "); split(b, B, " ")
        idle_a = A[5] + A[6]; idle_b = B[5] + B[6]
        total_a = 0; total_b = 0
        for (i = 2; i <= 8; i++) { total_a += A[i]; total_b += B[i] }
        dt = total_b - total_a
        di = idle_b - idle_a
        if (dt <= 0) { print "--"; exit }
        printf "%.0f%%", (1 - di/dt) * 100
    }'
}

# ---------------------------------------------------------------------------
# statistics::ram_usage - "used/total (pct%)" using /proc/meminfo
# ---------------------------------------------------------------------------
statistics::ram_usage() {
    [[ -r /proc/meminfo ]] || { echo "--"; return; }

    awk '
        /^MemTotal:/ { total = $2 }
        /^MemAvailable:/ { avail = $2 }
        END {
            used = total - avail
            pct = (total > 0) ? (used / total) * 100 : 0
            printf "%.1fG/%.1fG (%.0f%%)", used/1024/1024, total/1024/1024, pct
        }
    ' /proc/meminfo
}

# ---------------------------------------------------------------------------
# statistics::network_speed - "down/up" in human-readable units per second,
# computed as a delta over successive calls using /proc/net/dev totals.
# ---------------------------------------------------------------------------
statistics::network_speed() {
    [[ -r /proc/net/dev ]] || { echo "-- / --"; return; }

    local rx tx now
    read -r rx tx < <(awk '
        /:/ {
            gsub(/^ +/, "")
            split($0, f, ":")
            iface = f[1]
            if (iface == "lo") next
            split(f[2], cols, " ")
            rx += cols[1]
            tx += cols[9]
        }
        END { print rx, tx }
    ' /proc/net/dev)

    now="$(util::now_epoch)"

    if [[ "$STATS_PREV_TS" == "0" ]]; then
        STATS_PREV_RX="$rx"; STATS_PREV_TX="$tx"; STATS_PREV_TS="$now"
        echo "-- / --"
        return
    fi

    local dt=$(( now - STATS_PREV_TS ))
    (( dt <= 0 )) && dt=1
    local drx=$(( rx - STATS_PREV_RX ))
    local dtx=$(( tx - STATS_PREV_TX ))
    (( drx < 0 )) && drx=0
    (( dtx < 0 )) && dtx=0

    STATS_PREV_RX="$rx"; STATS_PREV_TX="$tx"; STATS_PREV_TS="$now"

    printf '%s/s ↓ / %s/s ↑' "$(util::human_bytes $((drx / dt)))" "$(util::human_bytes $((dtx / dt)))"
}

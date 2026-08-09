#!/usr/bin/env bash
# =============================================================================
# lib/dashboard.sh - Fullscreen dashboard orchestration and rendering
# =============================================================================
# This is the only module that draws to the screen. It launches the pacman/
# yay/flatpak workers as background jobs, polls their state files (written
# via lib/cache.sh), and redraws the dashboard in place. It also owns the
# keyboard-shortcut event loop.
# =============================================================================

[[ -n "${ARCH_UPDATER_DASHBOARD_LOADED:-}" ]] && return 0
ARCH_UPDATER_DASHBOARD_LOADED=1

DASH_ROOT=""
DASH_STATE_DIR=""
DASH_SHOW_LOG="false"
DASH_COMPACT="${COMPACT_MODE:-false}"
DASH_OVERLAY=""              # "" | help | summary | downloads
DASH_PAUSED="false"
DASH_QUITTING="false"
DASH_START_EPOCH=0

DASH_PID_PACMAN=""
DASH_PID_YAY=""
DASH_PID_FLATPAK=""

# ---------------------------------------------------------------------------
# dashboard::run <root> - main entry point, called after the preflight/scan
# stages in arch-updater.sh have completed.
# ---------------------------------------------------------------------------
dashboard::run() {
    DASH_ROOT="$1"
    DASH_STATE_DIR="$STATE_DIR"
    DASH_START_EPOCH="$(util::now_epoch)"

    trap 'dashboard::_on_exit' EXIT
    trap 'dashboard::_force_quit' SIGINT SIGTERM

    ui::init
    dashboard::_spawn_workers

    local last_draw=0
    while true; do
        dashboard::_handle_keys

        # Draw at most every REFRESH_RATE seconds to avoid flooding the
        # terminal with redraws.
        local now
        now="$(date +%s.%N)"
        if awk -v n="$now" -v l="$last_draw" -v r="${REFRESH_RATE:-0.25}" 'BEGIN{exit !(n-l>=r)}'; then
            dashboard::_draw_frame
            last_draw="$now"
        fi

        if dashboard::_all_workers_done && [[ -z "$DASH_OVERLAY" ]]; then
            dashboard::_on_workers_finished
            break
        fi

        sleep 0.03
    done

    # Keep the finished dashboard visible until the user presses a key.
    dashboard::_draw_frame
    ui::goto "$UI_TERM_ROWS" 1
    printf '%s' "$(ui::dim 'Press any key to exit...')"
    local k=""
    while [[ -z "$k" ]]; do
        k="$(ui::read_key)"
        sleep 0.05
    done
}

# ---------------------------------------------------------------------------
# dashboard::_on_exit - trap handler, always restores the terminal
# ---------------------------------------------------------------------------
dashboard::_on_exit() {
    ui::restore
}

# ---------------------------------------------------------------------------
# dashboard::_force_quit - Ctrl+C / SIGTERM handler. Unlike "Q" (which waits
# for the current package to finish), this restores the terminal and exits
# right away, leaving any in-flight worker processes to terminate on their
# own (pacman/yay/flatpak handle interrupted transactions safely on retry).
# ---------------------------------------------------------------------------
dashboard::_force_quit() {
    local pid
    for pid in "$DASH_PID_PACMAN" "$DASH_PID_YAY" "$DASH_PID_FLATPAK"; do
        [[ -z "$pid" ]] && continue
        kill -0 "$pid" 2>/dev/null && kill -TERM "$pid" 2>/dev/null
    done
    ui::restore
    printf '\nForce quit — terminal restored.\n'
    exit 130
}

# ---------------------------------------------------------------------------
# dashboard::_spawn_workers - launch each enabled package manager's update
# function as a background job.
# ---------------------------------------------------------------------------
dashboard::_spawn_workers() {
    if [[ "${ENABLE_PACMAN:-true}" == "true" ]] && pacman::available; then
        ( pacman::run_updates "$DASH_STATE_DIR" ) &
        DASH_PID_PACMAN=$!
    else
        cache::set_many "$DASH_STATE_DIR" "pacman" "STATUS=Finished" "OVERALL_PCT=100" "TOTAL=0"
    fi

    if [[ "${ENABLE_YAY:-true}" == "true" ]] && yay::available; then
        ( yay::run_updates "$DASH_STATE_DIR" ) &
        DASH_PID_YAY=$!
    else
        cache::set_many "$DASH_STATE_DIR" "yay" "STATUS=Finished" "OVERALL_PCT=100" "TOTAL=0"
    fi

    if [[ "${ENABLE_FLATPAK:-true}" == "true" ]] && flatpak::available; then
        ( flatpak::run_updates "$DASH_STATE_DIR" ) &
        DASH_PID_FLATPAK=$!
    else
        cache::set_many "$DASH_STATE_DIR" "flatpak" "STATUS=Finished" "OVERALL_PCT=100" "TOTAL=0"
    fi
}

# ---------------------------------------------------------------------------
# dashboard::_all_workers_done - true once every spawned worker has exited
# ---------------------------------------------------------------------------
dashboard::_all_workers_done() {
    local pid
    for pid in "$DASH_PID_PACMAN" "$DASH_PID_YAY" "$DASH_PID_FLATPAK"; do
        [[ -z "$pid" ]] && continue
        kill -0 "$pid" 2>/dev/null && return 1
    done
    return 0
}

# ---------------------------------------------------------------------------
# dashboard::_on_workers_finished - notifications + optional cleanup once
# all package managers have completed their pass.
# ---------------------------------------------------------------------------
dashboard::_on_workers_finished() {
    local failed
    failed="$(cache::failure_count "$DASH_STATE_DIR")"

    if (( failed > 0 )); then
        notifier::failed "$failed package(s) failed to update. Press R to retry or S for summary."
    else
        notifier::finished "All packages updated successfully."
    fi

    if [[ "${CLEANUP_ENABLED:-false}" == "true" ]]; then
        cache::set "$DASH_STATE_DIR" "control" "CLEANUP_STATUS" "Running"
        local freed
        freed="$(cleanup::run)"
        cache::set "$DASH_STATE_DIR" "control" "CLEANUP_STATUS" "Done"
        cache::set "$DASH_STATE_DIR" "control" "CLEANUP_FREED" "$freed"
        notifier::cleanup_complete "Freed approximately ${freed} MB"
    fi
}

# ---------------------------------------------------------------------------
# dashboard::_handle_keys - poll for a keypress and dispatch to an action
# ---------------------------------------------------------------------------
dashboard::_handle_keys() {
    local key
    key="$(ui::read_key)"
    [[ -z "$key" ]] && return

    if [[ -n "$DASH_OVERLAY" ]]; then
        # Any key dismisses an overlay.
        DASH_OVERLAY=""
        return
    fi

    case "$key" in
        "$KEY_QUIT")
            DASH_QUITTING="true"
            cache::set_flag "$DASH_STATE_DIR" "QUIT" "true"
            ;;
        "$KEY_LOG_TOGGLE")
            [[ "$DASH_SHOW_LOG" == "true" ]] && DASH_SHOW_LOG="false" || DASH_SHOW_LOG="true"
            ;;
        "$KEY_PAUSE")
            dashboard::_toggle_pause
            ;;
        "$KEY_RETRY_FAILED")
            dashboard::_retry_failed
            ;;
        "$KEY_CLEANUP_TOGGLE")
            [[ "$CLEANUP_ENABLED" == "true" ]] && CLEANUP_ENABLED="false" || CLEANUP_ENABLED="true"
            ;;
        "$KEY_SUMMARY")
            DASH_OVERLAY="summary"
            ;;
        "$KEY_DOWNLOAD_STATS")
            DASH_OVERLAY="downloads"
            ;;
        "$KEY_THEME_SWITCH")
            THEME="$(parser::next_theme "$THEME")"
            parser::load_theme "$DASH_ROOT" "$THEME"
            ;;
        "$KEY_COMPACT_TOGGLE")
            [[ "$DASH_COMPACT" == "true" ]] && DASH_COMPACT="false" || DASH_COMPACT="true"
            ;;
        "$KEY_EXPORT")
            dashboard::_export_report
            ;;
        "$KEY_HELP"|"$KEY_HELP_ALT")
            DASH_OVERLAY="help"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# dashboard::_toggle_pause - best-effort pause/resume of running workers via
# process-group signals. Some in-flight downloads may finish before the stop
# signal is delivered; this is intentional (see "P" shortcut docs in README).
# ---------------------------------------------------------------------------
dashboard::_toggle_pause() {
    local pid sig
    if [[ "$DASH_PAUSED" == "true" ]]; then
        DASH_PAUSED="false"; sig="CONT"
    else
        DASH_PAUSED="true"; sig="STOP"
    fi
    for pid in "$DASH_PID_PACMAN" "$DASH_PID_YAY" "$DASH_PID_FLATPAK"; do
        [[ -z "$pid" ]] && continue
        kill -0 "$pid" 2>/dev/null && kill "-$sig" "$pid" 2>/dev/null
    done
    cache::set_flag "$DASH_STATE_DIR" "PAUSED" "$DASH_PAUSED"
}

# ---------------------------------------------------------------------------
# dashboard::_retry_failed - re-run only packages recorded in failures.log
# ---------------------------------------------------------------------------
dashboard::_retry_failed() {
    local failures
    failures="$(cache::all_failures "$DASH_STATE_DIR")"
    [[ -z "$failures" ]] && return

    : > "$DASH_STATE_DIR/failures.log"

    if [[ "${ENABLE_PACMAN:-true}" == "true" ]] && pacman::available && \
       echo "$failures" | grep -q '|pacman|'; then
        ( pacman::run_updates "$DASH_STATE_DIR" ) &
        DASH_PID_PACMAN=$!
    fi
    if [[ "${ENABLE_YAY:-true}" == "true" ]] && yay::available && \
       echo "$failures" | grep -q '|yay|'; then
        ( yay::run_updates "$DASH_STATE_DIR" ) &
        DASH_PID_YAY=$!
    fi
    if [[ "${ENABLE_FLATPAK:-true}" == "true" ]] && flatpak::available && \
       echo "$failures" | grep -q '|flatpak|'; then
        ( flatpak::run_updates "$DASH_STATE_DIR" ) &
        DASH_PID_FLATPAK=$!
    fi
    notifier::retry_complete "Retry pass launched for previously failed packages"
}

# ---------------------------------------------------------------------------
# dashboard::_export_report - write a plain-text summary report to logs/
# ---------------------------------------------------------------------------
dashboard::_export_report() {
    local out="$LOG_DIR/report-$(date '+%Y%m%d-%H%M%S').txt"
    {
        echo "Arch Universal Updater - Update Report"
        echo "Generated: $(util::now_iso)"
        echo "========================================"
        echo
        echo "Pacman:  $(cache::get "$DASH_STATE_DIR" pacman COMPLETED 0)/$(cache::get "$DASH_STATE_DIR" pacman TOTAL 0) completed"
        echo "Yay:     $(cache::get "$DASH_STATE_DIR" yay COMPLETED 0)/$(cache::get "$DASH_STATE_DIR" yay TOTAL 0) completed"
        echo "Flatpak: $(cache::get "$DASH_STATE_DIR" flatpak COMPLETED 0)/$(cache::get "$DASH_STATE_DIR" flatpak TOTAL 0) completed"
        echo
        echo "Failures: $(cache::failure_count "$DASH_STATE_DIR")"
        cache::all_failures "$DASH_STATE_DIR"
    } > "$out"
    cache::set "$DASH_STATE_DIR" "control" "LAST_EXPORT" "$out"
}

# =============================================================================
# Rendering
# =============================================================================

# ---------------------------------------------------------------------------
# dashboard::_draw_frame - redraw the entire dashboard in place
# ---------------------------------------------------------------------------
dashboard::_draw_frame() {
    ui::update_dimensions
    local width=$(( UI_TERM_COLS - 2 ))
    (( width > 100 )) && width=100
    (( width < 40 )) && width=40

    # --- Height-aware layout ------------------------------------------------
    # Fixed line counts for each section, matching exactly what each
    # dashboard::_draw_panel_* function emits (box top + content lines +
    # box bottom). These must stay in sync with the panel renderers below.
    local LINES_HEADER=2 LINES_FOOTER=2
    local LINES_PACMAN=5 LINES_YAY=5 LINES_FLATPAK=6
    local LINES_SYSTEM=6 LINES_RECENT=7 LINES_COMPACT=5
    local LINES_LOG=8   # worst case: box top/bottom + up to 6 tailed lines

    local avail="$UI_TERM_ROWS"
    (( avail < 10 )) && avail=10

    local used=$(( LINES_HEADER + LINES_FOOTER ))
    local body_essential
    if [[ "$DASH_COMPACT" == "true" ]]; then
        body_essential="$LINES_COMPACT"
    else
        body_essential=$(( LINES_PACMAN + LINES_YAY + LINES_FLATPAK ))
    fi
    used=$(( used + body_essential ))

    # Terminal is too small even for the header/footer/manager panels: show
    # a short message instead of a layout that would force the terminal to
    # scroll (which is what produced the "flickering" behavior).
    if (( used > avail )) && [[ -z "$DASH_OVERLAY" ]]; then
        local frame_small
        frame_small="$(
            printf '\e[H'
            dashboard::_draw_header "$width"
            printf '%s\n' "$(ui::color_fg "$COLOR_WARNING" "Terminal too small to draw the dashboard (need >= ${used} rows, have ${avail}).")"
            printf '%s\n' "$(ui::dim 'Resize your terminal, or press F for compact mode.')"
            dashboard::_draw_footer "$width"
            printf '\e[J'
        )"
        printf '%s' "$frame_small"
        return
    fi

    # Optional panels are added only if they fit in whatever room is left,
    # in priority order (system info, then recent packages, then the live
    # log if the user asked to see it). This guarantees the dashboard never
    # exceeds the terminal's height regardless of how small it is.
    local remaining=$(( avail - used ))
    local show_system="false" show_recent="false" show_log="false"

    if (( remaining >= LINES_SYSTEM )); then
        show_system="true"
        remaining=$(( remaining - LINES_SYSTEM ))
    fi
    if (( remaining >= LINES_RECENT )); then
        show_recent="true"
        remaining=$(( remaining - LINES_RECENT ))
    fi
    if [[ "$DASH_SHOW_LOG" == "true" ]] && (( remaining >= LINES_LOG )); then
        show_log="true"
        remaining=$(( remaining - LINES_LOG ))
    fi

    # Build the entire frame into a single buffer and emit it with one
    # write. Redrawing line-by-line (or clearing the screen first) causes
    # visible flicker because the terminal briefly shows a blank/partial
    # screen between the clear and the repaint. Writing one full frame in
    # a single printf avoids that: the cursor is repositioned to the top
    # left, every line is overwritten in place, and only the very end of
    # the frame clears anything left over from a previous, taller frame.
    local frame
    frame="$(
        printf '\e[H'   # cursor to row 1, col 1 (no screen clear)
        dashboard::_draw_header "$width"

        if [[ -n "$DASH_OVERLAY" ]]; then
            dashboard::_draw_overlay "$width"
        elif [[ "$DASH_COMPACT" == "true" ]]; then
            dashboard::_draw_compact "$width"
            [[ "$show_log" == "true" ]] && dashboard::_draw_panel_log "$width"
        else
            dashboard::_draw_panel_pacman "$width"
            dashboard::_draw_panel_yay "$width"
            dashboard::_draw_panel_flatpak "$width"
            [[ "$show_system" == "true" ]] && dashboard::_draw_panel_system "$width"
            [[ "$show_recent" == "true" ]] && dashboard::_draw_panel_recent "$width"
            [[ "$show_log" == "true" ]] && dashboard::_draw_panel_log "$width"
        fi

        dashboard::_draw_footer "$width"

        # Wipe anything left over below this frame from a previous, taller
        # one (e.g. after toggling out of compact mode or closing the log
        # panel), without ever blanking the part we just drew.
        printf '\e[J'
    )"

    printf '%s' "$frame"
}

# ---------------------------------------------------------------------------
# dashboard::_draw_header <width>
# ---------------------------------------------------------------------------
dashboard::_draw_header() {
    local width="$1"
    local title=" Arch Universal Updater "
    local elapsed=$(( $(util::now_epoch) - DASH_START_EPOCH ))
    local status="RUNNING"
    [[ "$DASH_QUITTING" == "true" ]] && status="QUITTING"
    [[ "$DASH_PAUSED" == "true" ]] && status="PAUSED"
    dashboard::_all_workers_done && status="DONE"

    local right=" ${status} | $(util::human_time "$elapsed") | theme:${THEME} "
    local pad=$(( width - ${#title} - ${#right} ))
    (( pad < 1 )) && pad=1

    printf '%s%*s%s\n' \
        "$(ui::bold "$(ui::color_fg "$COLOR_ACCENT" "$title")")" \
        "$pad" "" \
        "$(ui::color_fg "$COLOR_MUTED" "$right")"
    ui::color_fg "$COLOR_BORDER" "$(ui::hr "$width")"
    printf '\n'
}

# ---------------------------------------------------------------------------
# dashboard::_draw_footer <width>
# ---------------------------------------------------------------------------
dashboard::_draw_footer() {
    local width="$1"
    ui::color_fg "$COLOR_BORDER" "$(ui::hr "$width")"
    printf '\n'
    local hint="[${KEY_QUIT}]Quit [${KEY_LOG_TOGGLE}]Log [${KEY_PAUSE}]Pause [${KEY_RETRY_FAILED}]Retry [${KEY_CLEANUP_TOGGLE}]Cleanup [${KEY_SUMMARY}]Summary [${KEY_DOWNLOAD_STATS}]Downloads [${KEY_THEME_SWITCH}]Theme [${KEY_COMPACT_TOGGLE}]Compact [${KEY_EXPORT}]Export [${KEY_HELP}]Help"
    printf '%s' "$(ui::color_fg "$COLOR_MUTED" "${hint:0:$width}")"
}

dashboard::_draw_panel_pacman() {
    local width="$1"
    local status pkg overall completed total failed
    status="$(cache::get "$DASH_STATE_DIR" pacman STATUS Waiting)"
    pkg="$(cache::get "$DASH_STATE_DIR" pacman CURRENT_PKG -)"
    overall="$(cache::get "$DASH_STATE_DIR" pacman OVERALL_PCT 0)"
    completed="$(cache::get "$DASH_STATE_DIR" pacman COMPLETED 0)"
    total="$(cache::get "$DASH_STATE_DIR" pacman TOTAL 0)"
    failed="$(cache::get "$DASH_STATE_DIR" pacman FAILED_COUNT 0)"

    ui::box_top "$width" "PACMAN  (${completed}/${total})" "$COLOR_PACMAN"
    ui::box_line "$width" "Status: $(ui::color_fg "$COLOR_TEXT" "$status")   Failed: $(ui::color_fg "$COLOR_ERROR" "$failed")" "$COLOR_PACMAN"
    ui::box_line "$width" "Package: $(ui::color_fg "$COLOR_TEXT" "$pkg")" "$COLOR_PACMAN"
    ui::box_line "$width" "Overall: $(progress::bar_with_label "$overall" 30 "$COLOR_PACMAN")" "$COLOR_PACMAN"
    ui::box_bottom "$width" "$COLOR_PACMAN"
}

dashboard::_draw_panel_yay() {
    local width="$1"
    local status pkg overall completed total stage failed elapsed
    status="$(cache::get "$DASH_STATE_DIR" yay STATUS Waiting)"
    pkg="$(cache::get "$DASH_STATE_DIR" yay CURRENT_PKG -)"
    overall="$(cache::get "$DASH_STATE_DIR" yay OVERALL_PCT 0)"
    completed="$(cache::get "$DASH_STATE_DIR" yay COMPLETED 0)"
    total="$(cache::get "$DASH_STATE_DIR" yay TOTAL 0)"
    stage="$(cache::get "$DASH_STATE_DIR" yay STAGE -)"
    failed="$(cache::get "$DASH_STATE_DIR" yay FAILED_COUNT 0)"
    elapsed="$(cache::get "$DASH_STATE_DIR" yay ELAPSED 0)"

    ui::box_top "$width" "YAY (AUR)  (${completed}/${total})" "$COLOR_YAY"
    ui::box_line "$width" "Status: $(ui::color_fg "$COLOR_TEXT" "$status")   Failed: $(ui::color_fg "$COLOR_ERROR" "$failed")   Elapsed: $(util::human_time "$elapsed")" "$COLOR_YAY"
    ui::box_line "$width" "Package: $(ui::color_fg "$COLOR_TEXT" "$pkg")   Stage: $(ui::color_fg "$COLOR_TEXT" "$stage")" "$COLOR_YAY"
    ui::box_line "$width" "Overall: $(progress::bar_with_label "$overall" 30 "$COLOR_YAY")" "$COLOR_YAY"
    ui::box_bottom "$width" "$COLOR_YAY"
}

dashboard::_draw_panel_flatpak() {
    local width="$1"
    local status pkg overall completed total pct failed
    status="$(cache::get "$DASH_STATE_DIR" flatpak STATUS Waiting)"
    pkg="$(cache::get "$DASH_STATE_DIR" flatpak CURRENT_PKG -)"
    overall="$(cache::get "$DASH_STATE_DIR" flatpak OVERALL_PCT 0)"
    completed="$(cache::get "$DASH_STATE_DIR" flatpak COMPLETED 0)"
    total="$(cache::get "$DASH_STATE_DIR" flatpak TOTAL 0)"
    pct="$(cache::get "$DASH_STATE_DIR" flatpak CURRENT_PCT 0)"
    failed="$(cache::get "$DASH_STATE_DIR" flatpak FAILED_COUNT 0)"

    ui::box_top "$width" "FLATPAK  (${completed}/${total})" "$COLOR_FLATPAK"
    ui::box_line "$width" "Status: $(ui::color_fg "$COLOR_TEXT" "$status")   Failed: $(ui::color_fg "$COLOR_ERROR" "$failed")" "$COLOR_FLATPAK"
    ui::box_line "$width" "Package: $(ui::color_fg "$COLOR_TEXT" "$pkg")" "$COLOR_FLATPAK"
    ui::box_line "$width" "Package Progress: $(progress::bar_with_label "$pct" 30 "$COLOR_FLATPAK")" "$COLOR_FLATPAK"
    ui::box_line "$width" "Overall: $(progress::bar_with_label "$overall" 30 "$COLOR_FLATPAK")" "$COLOR_FLATPAK"
    ui::box_bottom "$width" "$COLOR_FLATPAK"
}

dashboard::_draw_panel_system() {
    local width="$1"
    local cpu ram net elapsed failed logpath
    cpu="$(statistics::cpu_usage)"
    ram="$(statistics::ram_usage)"
    net="$(statistics::network_speed)"
    elapsed=$(( $(util::now_epoch) - DASH_START_EPOCH ))
    failed="$(cache::failure_count "$DASH_STATE_DIR")"
    logpath="$(logger::path)"

    ui::box_top "$width" "System Information" "$COLOR_BORDER"
    ui::box_line "$width" "CPU: $(ui::color_fg "$COLOR_TEXT" "$cpu")   RAM: $(ui::color_fg "$COLOR_TEXT" "$ram")" "$COLOR_BORDER"
    ui::box_line "$width" "Network: $(ui::color_fg "$COLOR_TEXT" "$net")" "$COLOR_BORDER"
    ui::box_line "$width" "Elapsed: $(util::human_time "$elapsed")   Failed packages: $(ui::color_fg "$COLOR_ERROR" "$failed")" "$COLOR_BORDER"
    ui::box_line "$width" "Log file: $(ui::color_fg "$COLOR_MUTED" "$logpath")" "$COLOR_BORDER"
    ui::box_bottom "$width" "$COLOR_BORDER"
}

dashboard::_draw_panel_recent() {
    local width="$1"
    ui::box_top "$width" "Recent Completed Packages" "$COLOR_SUCCESS"
    local lines
    mapfile -t lines < <(cache::recent_completed "$DASH_STATE_DIR" 5)
    if (( ${#lines[@]} == 0 )); then
        ui::box_line "$width" "$(ui::dim 'No packages completed yet')" "$COLOR_SUCCESS"
    else
        local l ts mgr pkg ver
        for l in "${lines[@]}"; do
            IFS='|' read -r ts mgr pkg ver <<< "$l"
            ui::box_line "$width" "$(ui::color_fg "$COLOR_SUCCESS" "✓") ${pkg} $(ui::dim "(${mgr}, ${ts#* })")" "$COLOR_SUCCESS"
        done
    fi
    ui::box_bottom "$width" "$COLOR_SUCCESS"
}

dashboard::_draw_panel_log() {
    local width="$1"
    ui::box_top "$width" "Live Log" "$COLOR_MUTED"
    local lines
    mapfile -t lines < <(logger::tail 6)
    if (( ${#lines[@]} == 0 )); then
        ui::box_line "$width" "$(ui::dim 'No log output yet')" "$COLOR_MUTED"
    else
        local l
        for l in "${lines[@]}"; do
            ui::box_line "$width" "$(ui::dim "${l:0:$((width-4))}")" "$COLOR_MUTED"
        done
    fi
    ui::box_bottom "$width" "$COLOR_MUTED"
}

dashboard::_draw_compact() {
    local width="$1"
    local p_ov y_ov f_ov p_st y_st f_st
    p_ov="$(cache::get "$DASH_STATE_DIR" pacman OVERALL_PCT 0)"
    y_ov="$(cache::get "$DASH_STATE_DIR" yay OVERALL_PCT 0)"
    f_ov="$(cache::get "$DASH_STATE_DIR" flatpak OVERALL_PCT 0)"
    p_st="$(cache::get "$DASH_STATE_DIR" pacman STATUS -)"
    y_st="$(cache::get "$DASH_STATE_DIR" yay STATUS -)"
    f_st="$(cache::get "$DASH_STATE_DIR" flatpak STATUS -)"

    ui::box_top "$width" "Compact Overview" "$COLOR_BORDER"
    ui::box_line "$width" "Pacman   $(progress::bar_with_label "$p_ov" 24 "$COLOR_PACMAN")  ${p_st}" "$COLOR_BORDER"
    ui::box_line "$width" "Yay      $(progress::bar_with_label "$y_ov" 24 "$COLOR_YAY")  ${y_st}" "$COLOR_BORDER"
    ui::box_line "$width" "Flatpak  $(progress::bar_with_label "$f_ov" 24 "$COLOR_FLATPAK")  ${f_st}" "$COLOR_BORDER"
    ui::box_bottom "$width" "$COLOR_BORDER"
}

dashboard::_draw_overlay() {
    local width="$1"
    case "$DASH_OVERLAY" in
        help)     dashboard::_draw_help_overlay "$width" ;;
        summary)  dashboard::_draw_summary_overlay "$width" ;;
        downloads) dashboard::_draw_downloads_overlay "$width" ;;
    esac
}

dashboard::_draw_help_overlay() {
    local width="$1"
    ui::box_top "$width" "Keyboard Shortcuts" "$COLOR_ACCENT"
    ui::box_line "$width" "${KEY_QUIT}          Quit safely after current package" "$COLOR_ACCENT"
    ui::box_line "$width" "Ctrl+C      Force quit immediately" "$COLOR_ACCENT"
    ui::box_line "$width" "${KEY_LOG_TOGGLE}          Toggle live log panel" "$COLOR_ACCENT"
    ui::box_line "$width" "${KEY_PAUSE}          Pause updates after the current package" "$COLOR_ACCENT"
    ui::box_line "$width" "${KEY_RETRY_FAILED}          Retry failed packages only" "$COLOR_ACCENT"
    ui::box_line "$width" "${KEY_CLEANUP_TOGGLE}          Toggle cleanup stage" "$COLOR_ACCENT"
    ui::box_line "$width" "${KEY_SUMMARY}          Show update summary" "$COLOR_ACCENT"
    ui::box_line "$width" "${KEY_DOWNLOAD_STATS}          Show download statistics" "$COLOR_ACCENT"
    ui::box_line "$width" "${KEY_THEME_SWITCH}          Switch themes" "$COLOR_ACCENT"
    ui::box_line "$width" "${KEY_COMPACT_TOGGLE}          Toggle compact/full dashboard" "$COLOR_ACCENT"
    ui::box_line "$width" "${KEY_EXPORT}          Export update report" "$COLOR_ACCENT"
    ui::box_line "$width" "${KEY_HELP} / ${KEY_HELP_ALT}        Show this help" "$COLOR_ACCENT"
    ui::box_line "$width" "" "$COLOR_ACCENT"
    ui::box_line "$width" "$(ui::dim 'Press any key to close')" "$COLOR_ACCENT"
    ui::box_bottom "$width" "$COLOR_ACCENT"
}

dashboard::_draw_summary_overlay() {
    local width="$1"
    ui::box_top "$width" "Update Summary" "$COLOR_ACCENT"
    ui::box_line "$width" "Pacman:   $(cache::get "$DASH_STATE_DIR" pacman COMPLETED 0)/$(cache::get "$DASH_STATE_DIR" pacman TOTAL 0) completed" "$COLOR_ACCENT"
    ui::box_line "$width" "Yay:      $(cache::get "$DASH_STATE_DIR" yay COMPLETED 0)/$(cache::get "$DASH_STATE_DIR" yay TOTAL 0) completed" "$COLOR_ACCENT"
    ui::box_line "$width" "Flatpak:  $(cache::get "$DASH_STATE_DIR" flatpak COMPLETED 0)/$(cache::get "$DASH_STATE_DIR" flatpak TOTAL 0) completed" "$COLOR_ACCENT"
    ui::box_line "$width" "Failed:   $(cache::failure_count "$DASH_STATE_DIR")" "$COLOR_ACCENT"
    ui::box_line "$width" "" "$COLOR_ACCENT"
    local lines
    mapfile -t lines < <(cache::all_failures "$DASH_STATE_DIR" | tail -n 5)
    if (( ${#lines[@]} > 0 )); then
        ui::box_line "$width" "$(ui::color_fg "$COLOR_ERROR" 'Recent failures:')" "$COLOR_ACCENT"
        local l ts mgr pkg reason retries
        for l in "${lines[@]}"; do
            IFS='|' read -r ts mgr pkg reason retries <<< "$l"
            ui::box_line "$width" "  $(ui::color_fg "$COLOR_ERROR" "✗") ${pkg} (${mgr})" "$COLOR_ACCENT"
        done
    fi
    ui::box_line "$width" "" "$COLOR_ACCENT"
    ui::box_line "$width" "$(ui::dim 'Press any key to close')" "$COLOR_ACCENT"
    ui::box_bottom "$width" "$COLOR_ACCENT"
}

dashboard::_draw_downloads_overlay() {
    local width="$1"
    ui::box_top "$width" "Download Statistics" "$COLOR_ACCENT"
    ui::box_line "$width" "Network: $(statistics::network_speed)" "$COLOR_ACCENT"
    ui::box_line "$width" "Pacman speed field:    $(cache::get "$DASH_STATE_DIR" pacman SPEED '--')" "$COLOR_ACCENT"
    ui::box_line "$width" "Pacman remaining:      $(cache::get "$DASH_STATE_DIR" pacman REMAINING '--')" "$COLOR_ACCENT"
    ui::box_line "$width" "Pacman ETA:            $(cache::get "$DASH_STATE_DIR" pacman ETA '--')" "$COLOR_ACCENT"
    ui::box_line "$width" "" "$COLOR_ACCENT"
    ui::box_line "$width" "$(ui::dim 'Press any key to close')" "$COLOR_ACCENT"
    ui::box_bottom "$width" "$COLOR_ACCENT"
}

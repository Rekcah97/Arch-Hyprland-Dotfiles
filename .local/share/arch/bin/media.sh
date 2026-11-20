#!/bin/bash
# Usage: media.sh play-pause | next | previous

# Prefer the player that is currently playing, else the first one found
player=$(playerctl -a status -f '{{playerName}} {{status}}' 2>/dev/null | awk '$2=="Playing"{print $1; exit}')
[ -z "$player" ] && player=$(playerctl -l 2>/dev/null | head -n1)
if [ -z "$player" ]; then
    swayosd-client --custom-icon media-playback-stop-symbolic --custom-message "No media player"
    exit 0
fi

pc()    { playerctl -p "$player" "$@" 2>/dev/null; }
title() { pc metadata xesam:title; }
track() { pc metadata --format '{{mpris:trackid}}|{{xesam:title}}'; }
short() { local t="$1"; [ ${#t} -gt 45 ] && echo "${t:0:45}…" || echo "$t"; }

osd() { swayosd-client --custom-icon "$1" --custom-message "$2"; }

case "$1" in
    play-pause)
        pc play-pause
        sleep 0.2
        t=$(short "$(title)")
        if [ "$(pc status)" = "Playing" ]; then
            msg="Playing"; icon=media-playback-start-symbolic
        else
            msg="Paused"; icon=media-playback-pause-symbolic
        fi
        [ -n "$t" ] && msg="$msg: $t"
        osd "$icon" "$msg"
        ;;

    next|previous)
        before=$(track)
        pc "$1"

        # Wait up to ~3s for the track to actually change
        changed=0
        for _ in $(seq 1 15); do
            sleep 0.2
            after=$(track)
            if [ -n "$after" ] && [ "$after" != "$before" ]; then
                changed=1
                break
            fi
        done

        t=$(short "$(title)")

        if [ "$1" = "next" ]; then
            icon=media-skip-forward-symbolic;  label="Next"
        else
            icon=media-skip-backward-symbolic; label="Previous"
        fi

        if [ "$changed" = 1 ] && [ -n "$t" ]; then
            osd "$icon" "$label: $t"
        else
            osd "$icon" "$label in queue"
        fi
        ;;

    *) exit 1 ;;
esac

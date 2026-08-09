#!/bin/bash

if (($# == 0)); then
  echo "Usage: launch-or-focus-tui [tui-command] [args...]"
  exit 1
fi

TUI_COMMAND="$1"
shift
TUI_ARGS="$@"

# Check if already running
if pgrep -x "$(basename "$TUI_COMMAND")" > /dev/null 2>&1; then
  echo "TUI $TUI_COMMAND is already running"
  exit 0
fi

# Launch in alacritty with FORCED title using -T flag
alacritty -T "$TUI_COMMAND" -e $TUI_COMMAND $TUI_ARGS &
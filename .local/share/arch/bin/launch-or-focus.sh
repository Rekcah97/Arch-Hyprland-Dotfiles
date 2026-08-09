#!/bin/bash

# Generic launch-or-focus script for Arch Linux
# Fixed process detection to avoid false positives

if (($# == 0)); then
  echo "Usage: launch-or-focus [window-pattern] [launch-command]"
  exit 1
fi

WINDOW_PATTERN="$1"
LAUNCH_COMMAND="${2:-$WINDOW_PATTERN}"

# Check if wmctrl is available (X11)
if command -v wmctrl &> /dev/null; then
  # Try to find and focus the window
  WINDOW_ID=$(wmctrl -lx 2>/dev/null | grep -i "$WINDOW_PATTERN" | head -n1 | awk '{print $1}')
  
  if [[ -n $WINDOW_ID ]]; then
    wmctrl -ia "$WINDOW_ID"
    exit 0
  fi
fi

# Check if process is already running (exclude grep itself)
if pgrep -x "$(basename "$WINDOW_PATTERN")" > /dev/null 2>&1; then
  echo "Process '$WINDOW_PATTERN' is already running"
  exit 0
fi

# Launch the application
echo "Launching: $LAUNCH_COMMAND"
setsid $LAUNCH_COMMAND &>/dev/null &
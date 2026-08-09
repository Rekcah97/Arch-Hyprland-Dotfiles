#!/bin/bash

# Launch wifi controls
rfkill unblock wifi 2>/dev/null

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Launch impala
"$SCRIPT_DIR/launch-or-focus-tui.sh" impala
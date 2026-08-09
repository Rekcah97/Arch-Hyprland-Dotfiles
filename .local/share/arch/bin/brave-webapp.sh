#!/bin/bash
# Brave Web App Launcher for Hyprland
# Usage: ./brave-webapp.sh <URL> <app-name>

if [ $# -lt 2 ]; then
    echo "Usage: $0 <URL> <app-name>"
    echo "Example: $0 https://app.slack.com Slack"
    exit 1
fi

URL="$1"
APP_NAME="$2"

# Launch Brave in app mode (chromeless window)
brave --app="$URL" \
      --class="brave-$APP_NAME" \
      --user-data-dir="$HOME/.config/brave-webapps/$APP_NAME" \
      --disable-features=TranslateUI \
      --disable-sync \
      --no-first-run &

echo "Launched $APP_NAME at $URL"

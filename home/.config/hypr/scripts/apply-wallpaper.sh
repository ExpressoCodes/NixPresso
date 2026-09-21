#!/usr/bin/env bash
# Apply hyprpaper wallpaper to a newly-connected monitor.
# Called from hyprland.lua's monitor.added event handler.
# Parses the new hyprpaper block config format (>= 0.8).
set -euo pipefail

MONITOR="${1:-}"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprpaper.conf"

[ -z "$MONITOR" ] && exit 1
[ -f "$CONF" ]    || exit 0

# Wait for hyprpaper to be running (it starts after hyprland.start, monitors fire earlier)
for i in $(seq 1 20); do
    pgrep -x hyprpaper > /dev/null && break
    sleep 0.5
done
pgrep -x hyprpaper > /dev/null || exit 0

sleep 0.5  # let hyprpaper finish its own startup render

# Parse wallpaper blocks to find explicit monitor entry or fallback (empty monitor)
WALLPAPER=""
FALLBACK=""
IN_BLOCK=0
BLOCK_MONITOR=""
BLOCK_PATH=""

while IFS= read -r line; do
    line=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    if [[ "$line" == *"wallpaper"*"{"* ]]; then
        IN_BLOCK=1
        BLOCK_MONITOR=""
        BLOCK_PATH=""
    elif [[ "$line" == "}" ]] && [ "$IN_BLOCK" -eq 1 ]; then
        IN_BLOCK=0
        if [ -n "$BLOCK_PATH" ]; then
            if [ "$BLOCK_MONITOR" = "$MONITOR" ]; then
                WALLPAPER="$BLOCK_PATH"
            elif [ -z "$BLOCK_MONITOR" ] && [ -z "$FALLBACK" ]; then
                FALLBACK="$BLOCK_PATH"
            fi
        fi
    elif [ "$IN_BLOCK" -eq 1 ]; then
        if [[ "$line" =~ ^monitor[[:space:]]*=[[:space:]]*(.*) ]]; then
            BLOCK_MONITOR="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^path[[:space:]]*=[[:space:]]*(.*) ]]; then
            BLOCK_PATH="${BASH_REMATCH[1]}"
            BLOCK_PATH="${BLOCK_PATH/#\~/$HOME}"  # expand ~
        fi
    fi
done < "$CONF"

[ -z "$WALLPAPER" ] && WALLPAPER="$FALLBACK"
[ -z "$WALLPAPER" ] && exit 0

hyprctl hyprpaper wallpaper "${MONITOR},${WALLPAPER}"

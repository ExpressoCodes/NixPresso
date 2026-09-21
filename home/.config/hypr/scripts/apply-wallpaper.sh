#!/usr/bin/env bash
# Apply hyprpaper wallpaper to a newly-connected monitor.
# Called from hyprland.lua's monitor.added event handler.
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

# Prefer an explicit per-monitor entry, fall back to the wildcard (empty monitor)
WALLPAPER=$(grep "^wallpaper = ${MONITOR}," "$CONF" 2>/dev/null | head -1 | cut -d',' -f2-)
if [ -z "$WALLPAPER" ]; then
    WALLPAPER=$(grep "^wallpaper = ," "$CONF" 2>/dev/null | head -1 | sed 's/^wallpaper = ,//')
fi

[ -z "$WALLPAPER" ] && exit 0

hyprctl hyprpaper preload "$WALLPAPER" 2>/dev/null || true
hyprctl hyprpaper wallpaper "${MONITOR},${WALLPAPER}"

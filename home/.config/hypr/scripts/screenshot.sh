#!/usr/bin/env bash
# Screenshot with one slurp overlay:
#   left-click on a window -> that window
#   click-and-drag         -> custom area
#   right-click            -> whole monitor under the cursor
#   Esc                    -> cancel
# Result is saved to ~/Pictures/Screenshots and copied to the clipboard.
#
# slurp can't tell mouse buttons apart, so right-click is a Hyprland bind
# (screenshotRightClick in hyprland.lua) that is only enabled while the overlay
# is up. It re-runs this script with --right-click, which drops a marker and
# closes slurp.

marker="${XDG_RUNTIME_DIR:-/tmp}/screenshot-right-click"

if [[ $1 == --right-click ]]; then
    touch "$marker"
    pkill -x slurp
    exit 0
fi

dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
mkdir -p "$dir"
file="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"

# Name of the monitor containing the cursor.
monitor_under_cursor() {
    local pos
    pos=$(hyprctl cursorpos | tr -d ' ')
    hyprctl monitors | awk -v cx="${pos%,*}" -v cy="${pos#*,}" '
        function check() {
            if (name != "" && cx >= x && cx < x + w / s && cy >= y && cy < y + h / s) { print name; exit }
        }
        /^Monitor /  { check(); name = $2; s = 1 }
        /^\t[0-9]+x[0-9]+@/ {
            split($1, res, /[x@]/); w = res[1]; h = res[2]
            split($3, off, "x"); x = off[1]; y = off[2]
        }
        /^\tscale:/  { s = $2 }
        END          { check() }
    '
}

# Boxes of windows on the currently active workspace per monitor.
# hyprctl reports visible:1 for windows on inactive workspaces too, so we
# cross-check each window's workspace against the monitor's active workspace.
_active_ws=$(hyprctl monitors | awk '
    /^Monitor / { s = $0; sub(/.*\(ID /, "", s); sub(/\).*/, "", s); id = s + 0 }
    /^\tactive workspace:/ { print id "\t" $3 }
')
windows=$(hyprctl clients | awk -v aws="$_active_ws" '
    BEGIN {
        n = split(aws, lines, "\n")
        for (i = 1; i <= n; i++) {
            split(lines[i], p, "\t")
            if (p[1] != "") active[p[1]] = p[2]
        }
    }
    function emit() {
        if (mapped && !hidden && (mon in active) && ws == active[mon] && at != "")
            print at, size
        at = ""
    }
    /^Window /      { emit(); mapped = hidden = 0; ws = mon = at = "" }
    /^\tmapped:/    { mapped = $2 }
    /^\thidden:/    { hidden = $2 }
    /^\tworkspace:/ { ws = $2 }
    /^\tmonitor:/   { mon = $2 }
    /^\tat:/        { at = $2 }
    /^\tsize:/      { sub(",", "x", $2); size = $2 }
    END             { emit() }
')

rm -f "$marker"
hyprctl eval 'screenshotRightClick:set_enabled(true)' >/dev/null
trap "hyprctl eval 'screenshotRightClick:set_enabled(false)' >/dev/null" EXIT

# -o adds each monitor as a box, so a left-click on empty desktop/bar also
# grabs the monitor; slurp picks the smallest box under the cursor, so windows
# win over monitors and a drag overrides both.
geom=$(printf '%s\n' "$windows" | slurp -o -d \
    -b '#00000066' -c '#89b4faff' -s '#89b4fa22' -B '#ffffff11' -w 2)
status=$?

if [[ -e $marker ]]; then
    rm -f "$marker"
    grim -o "$(monitor_under_cursor)" "$file" || exit 1
elif (( status == 0 )); then
    grim -g "$geom" "$file" || exit 1
else
    exit 0  # cancelled
fi

wl-copy --type image/png < "$file"

gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.Notify \
    "screenshot" 0 "$file" "Screenshot saved" "$file (copied to clipboard)" \
    '[]' '{}' 3000 >/dev/null 2>&1

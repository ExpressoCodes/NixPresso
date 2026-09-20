#!/usr/bin/env bash
# Generates monitors.lua from currently connected monitors.
# Re-runs on every Hyprland start but only rewrites the file when
# the connected monitor set (names, modes, positions) changes.

set -euo pipefail

HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
OUT="$HYPR_DIR/monitors.lua"
HASH_FILE="$HYPR_DIR/.monitors.hash"

# Bail gracefully if hyprctl isn't ready
MONITORS_JSON=$(hyprctl monitors -j 2>/dev/null) || exit 0
[ -z "$MONITORS_JSON" ] && exit 0

# Stable hash over fields that affect the config; sort by name for stability
CURRENT_HASH=$(node -e "
const m = JSON.parse(process.argv[1]);
const key = m.map(({name,width,height,refreshRate,x,y,scale}) =>
    ({name,width,height,refreshRate,x,y,scale}))
  .sort((a,b) => a.name.localeCompare(b.name));
process.stdout.write(JSON.stringify(key));
" "$MONITORS_JSON" | sha256sum | cut -d' ' -f1)

STORED_HASH=$( [ -f "$HASH_FILE" ] && cat "$HASH_FILE" || echo "" )

# Nothing changed and file already exists: nothing to do
[ "$CURRENT_HASH" = "$STORED_HASH" ] && [ -f "$OUT" ] && exit 0

# Preserve the hyprland-settings managed block if it already exists in the file
HL_SETTINGS_BLOCK=""
if [ -f "$OUT" ]; then
    HL_SETTINGS_BLOCK=$(sed -n '/-- >>> hyprland-settings: monitors/,/-- <<< hyprland-settings: monitors/p' "$OUT")
fi

# Build the hl.monitor() lines via node
MONITOR_LINES=$(node -e "
const m = JSON.parse(process.argv[1]);
const lines = m.map(({name,width,height,refreshRate,x,y,scale}) =>
    \`hl.monitor({ output = \\\"\${name}\\\", mode = \\\"\${width}x\${height}@\${refreshRate}\\\", position = \\\"\${x}x\${y}\\\", scale = \\\"\${scale}\\\" })\`
);
process.stdout.write(lines.join('\n'));
" "$MONITORS_JSON")

# Write atomically
TMP=$(mktemp "$HYPR_DIR/.monitors.lua.XXXXXX")
trap 'rm -f "$TMP"' EXIT

{
    echo "-- Auto-generated from connected monitors — do not edit by hand."
    echo "-- Regenerated automatically when the connected monitor set changes."
    echo ""
    echo "$MONITOR_LINES"
    echo ""
    echo "-- Fallback: anything else gets sensible defaults"
    echo 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })'

    if [ -n "$HL_SETTINGS_BLOCK" ]; then
        echo ""
        echo "$HL_SETTINGS_BLOCK"
    else
        echo ""
        echo "-- >>> hyprland-settings: monitors (do not edit this line)"
        echo "-- <<< hyprland-settings: monitors (do not edit this line)"
    fi
} > "$TMP"

mv "$TMP" "$OUT"
printf '%s' "$CURRENT_HASH" > "$HASH_FILE"

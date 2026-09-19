#!/usr/bin/env bash
# Trigger a system tray DBus menu item by SNI id and label.
# Usage: tray-trigger.sh <sni-id> <item-label>
set -euo pipefail

SNI_ID="$1"
ITEM_LABEL="$2"

# Get all registered SNI services from Quickshell's watcher
WATCHER_OUT=$(busctl --user call org.kde.StatusNotifierWatcher \
    /StatusNotifierWatcher \
    org.freedesktop.DBus.Properties Get ss \
    org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems 2>/dev/null)

# Extract "service/path" entries (values in double-quotes that contain a /)
ENTRIES=$(printf '%s' "$WATCHER_OUT" | tr '"' '\n' | grep '/')

TARGET_SERVICE=""
TARGET_MENU_PATH=""

while IFS= read -r ENTRY; do
    [ -z "$ENTRY" ] && continue

    SERVICE="${ENTRY%%/*}"          # part before first /
    SNI_PATH="/${ENTRY#*/}"        # part from first / onward

    # Check if this service's SNI Id matches what QML reported
    ID=$(dbus-send --session --print-reply \
        --dest="$SERVICE" "$SNI_PATH" \
        org.freedesktop.DBus.Properties.Get \
        string:org.kde.StatusNotifierItem string:Id 2>/dev/null | \
        awk -F'"' '/string "/{print $2; exit}')

    [ "$ID" != "$SNI_ID" ] && continue

    # Found it — get the DBus menu path
    TARGET_MENU_PATH=$(dbus-send --session --print-reply \
        --dest="$SERVICE" "$SNI_PATH" \
        org.freedesktop.DBus.Properties.Get \
        string:org.kde.StatusNotifierItem string:Menu 2>/dev/null | \
        awk -F'"' '/object path "/{print $2; exit}')

    TARGET_SERVICE="$SERVICE"
    break
done <<< "$ENTRIES"

[ -z "$TARGET_SERVICE" ] && exit 1
[ -z "$TARGET_MENU_PATH" ] && exit 1

# Get the full menu layout (depth 10 covers nested submenus)
LAYOUT=$(busctl --user call "$TARGET_SERVICE" "$TARGET_MENU_PATH" \
    com.canonical.dbusmenu GetLayout "iias" 0 10 0 2>/dev/null)

# Find item ID: each item block starts with (ia{sv}av) ID NPROPS ...
# Use literal string replacement (no regex) to split on (ia{sv}av).
ITEM_ID=$(printf '%s' "$LAYOUT" | awk -v label="$ITEM_LABEL" '
{
    SEP = "\034"
    line = $0
    while ((idx = index(line, "(ia{sv}av)")) > 0) {
        line = substr(line, 1, idx-1) SEP substr(line, idx+10)
    }
    n = split(line, parts, SEP)
    for (i = 2; i <= n; i++) {
        chunk = parts[i]
        if (index(chunk, "\"" label "\"") > 0) {
            sub(/^[[:space:]]*/, "", chunk)
            match(chunk, /^[0-9]+/)
            if (RLENGTH > 0) {
                print substr(chunk, 1, RLENGTH)
                exit
            }
        }
    }
}')

[ -z "$ITEM_ID" ] && exit 1

# Trigger the item via DBus Event
busctl --user call "$TARGET_SERVICE" "$TARGET_MENU_PATH" \
    com.canonical.dbusmenu Event "isvu" "$ITEM_ID" "clicked" i 0 0 2>/dev/null

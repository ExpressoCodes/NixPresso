# Shared helpers sourced by install.sh and update.sh.
# Not executable directly.

# fuzzy_pick LABEL ITEMS DEFAULT
# Uses fzf when available; falls back to a grep+numbered-list picker.
fuzzy_pick() {
    local label="$1" items="$2" default="$3"
    if command -v fzf &>/dev/null; then
        local result
        result=$(printf '%s\n' "$items" | fzf --height=40% --reverse \
            --prompt="$label: " --query="$default" --select-1 --exit-0 2>/dev/null) \
            && echo "$result" && return
        # fzf aborted (ESC/Ctrl-C) — fall through to manual picker
    fi
    local query results count choice
    while true; do
        read -rp "  Filter $label (enter=show all) [default: $default]: " query
        if [ -z "$query" ]; then
            results=$(printf '%s\n' "$items")
        else
            results=$(printf '%s\n' "$items" | grep -i "$query" || true)
        fi
        if [ -z "$results" ]; then
            info "No matches for '$query' — try again."
            continue
        fi
        count=$(printf '%s\n' "$results" | wc -l)
        if [ "$count" -eq 1 ]; then
            printf '%s\n' "$results"; return
        fi
        if [ "$count" -gt 20 ]; then
            info "$count matches — showing first 20, refine your search for more."
            results=$(printf '%s\n' "$results" | head -20)
            count=20
        fi
        local i=1
        while IFS= read -r line; do
            printf "  %3d)  %s\n" "$i" "$line"
            ((i++))
        done <<< "$results"
        echo ""
        read -rp "  Pick [1–$count, or press enter to search again]: " choice
        [ -z "$choice" ] && continue
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
            printf '%s\n' "$results" | sed -n "${choice}p"; return
        fi
        info "Invalid choice — enter a number 1–$count."
    done
}

# is_placeholder VALUE — true if value looks like an unsubstituted token
is_placeholder() {
    [[ "$1" == your* ]]
}

select_timezone() {
    echo ""
    bold "Timezone"
    local detected
    detected=$(timedatectl show --property=Timezone --value 2>/dev/null \
        || cat /etc/timezone 2>/dev/null \
        || readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||' \
        || echo "")
    is_placeholder "$detected" && detected=""
    local zones
    zones=$(timedatectl list-timezones 2>/dev/null \
        || find /usr/share/zoneinfo -type f ! -name '*.tab' ! -name '*.list' \
            | sed 's|.*/zoneinfo/||' | sort)
    TIMEZONE=$(fuzzy_pick "Timezone" "$zones" "${detected:-UTC}")
    info "Selected: $TIMEZONE"
}

select_locale() {
    echo ""
    bold "Locale"
    local detected
    detected=$(localectl status 2>/dev/null | awk '/System Locale/{print $3}' | cut -d= -f2 || echo "")
    is_placeholder "$detected" && detected=""
    [ -z "$detected" ] && detected="${LANG:-}"
    [ -z "$detected" ] && detected="en_US.UTF-8"
    local locales
    locales=$(locale -a 2>/dev/null | grep -E 'UTF-8|utf8' | sed 's/utf8/UTF-8/' | sort -u \
        || printf '%s\n' \
            en_US.UTF-8 en_GB.UTF-8 en_IE.UTF-8 en_AU.UTF-8 en_CA.UTF-8 \
            de_DE.UTF-8 fr_FR.UTF-8 es_ES.UTF-8 it_IT.UTF-8 pt_PT.UTF-8 \
            pt_BR.UTF-8 nl_NL.UTF-8 pl_PL.UTF-8 ru_RU.UTF-8 ja_JP.UTF-8 \
            zh_CN.UTF-8 zh_TW.UTF-8 ko_KR.UTF-8 ar_SA.UTF-8 tr_TR.UTF-8)
    LOCALE=$(fuzzy_pick "Locale" "$locales" "$detected")
    info "Selected: $LOCALE"
}

select_keymap() {
    echo ""
    bold "Keyboard layout"
    local detected
    detected=$(localectl status 2>/dev/null | awk '/X11 Layout/{print $3}' || echo "")
    is_placeholder "$detected" && detected=""
    local layouts
    layouts=$(localectl list-x11-keymap-layouts 2>/dev/null \
        || find /usr/share/X11/xkb/symbols -maxdepth 1 -type f \
            | xargs -I{} basename {} | sort)
    KEYMAP=$(fuzzy_pick "Keyboard layout" "$layouts" "${detected:-us}")
    info "Selected: $KEYMAP"
}

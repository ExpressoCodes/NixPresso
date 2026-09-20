# Shared helpers sourced by install.sh and update.sh.
# Not executable directly.

# fuzzy_pick LABEL ITEMS DEFAULT
# Uses fzf when available (live filter). Otherwise: type a search term to
# filter the list, pick by number. ENTER alone always accepts the default.
fuzzy_pick() {
    local label="$1" items="$2" default="$3"

    if command -v fzf &>/dev/null; then
        local result
        result=$(printf '%s\n' "$items" | fzf --height=40% --reverse \
            --prompt="$label > " --query="$default" --select-1 --exit-0 2>/dev/null) \
            && { echo "$result"; return; }
        # ESC/Ctrl-C from fzf — fall through to text picker
    fi

    local query results count choice
    while true; do
        printf "  \033[1m%s\033[0m (ENTER=use default '%s', or type to search): " "$label" "$default" >&2
        read -r query
        if [ -z "$query" ]; then
            echo "$default"; return
        fi
        results=$(printf '%s\n' "$items" | grep -i "$query" || true)
        if [ -z "$results" ]; then
            printf '  No matches for "%s" — try again.\n' "$query" >&2
            continue
        fi
        count=$(printf '%s\n' "$results" | wc -l)
        if [ "$count" -eq 1 ]; then
            printf '%s\n' "$results"; return
        fi
        if [ "$count" -gt 20 ]; then
            printf '  %d matches — showing first 20, refine to narrow further.\n' "$count" >&2
            results=$(printf '%s\n' "$results" | head -20)
            count=20
        fi
        local i=1
        while IFS= read -r line; do
            printf "  %2d)  %s\n" "$i" "$line" >&2
            (( i++ ))
        done <<< "$results"
        printf "  Pick 1–%d, or ENTER to search again: " "$count" >&2
        read -r choice
        [ -z "$choice" ] && continue
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
            printf '%s\n' "$results" | sed -n "${choice}p"; return
        fi
        printf '  Invalid — enter a number 1–%d.\n' "$count" >&2
    done
}

# is_placeholder VALUE — true if value looks like an unsubstituted token
is_placeholder() {
    [[ "$1" == your* ]]
}

select_timezone() {
    echo "" >&2
    bold "Timezone" >&2
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
    info "Selected: $TIMEZONE" >&2
}

select_locale() {
    echo "" >&2
    bold "Locale" >&2
    local detected
    detected=$(localectl status 2>/dev/null | awk '/System Locale/{print $3}' | cut -d= -f2 || echo "")
    is_placeholder "$detected" && detected=""
    [ -z "$detected" ] && detected="${LANG:-}"
    is_placeholder "$detected" && detected=""
    # locale -a on NixOS only lists compiled-in locales — always use the full list
    local locales
    locales=$(printf '%s\n' \
        af_ZA.UTF-8 ar_AE.UTF-8 ar_SA.UTF-8 bg_BG.UTF-8 ca_ES.UTF-8 \
        cs_CZ.UTF-8 cy_GB.UTF-8 da_DK.UTF-8 de_AT.UTF-8 de_CH.UTF-8 \
        de_DE.UTF-8 el_GR.UTF-8 en_AU.UTF-8 en_CA.UTF-8 en_GB.UTF-8 \
        en_IE.UTF-8 en_IN.UTF-8 en_NZ.UTF-8 en_SG.UTF-8 en_US.UTF-8 \
        en_ZA.UTF-8 es_AR.UTF-8 es_CL.UTF-8 es_CO.UTF-8 es_ES.UTF-8 \
        es_MX.UTF-8 et_EE.UTF-8 fi_FI.UTF-8 fr_BE.UTF-8 fr_CA.UTF-8 \
        fr_CH.UTF-8 fr_FR.UTF-8 ga_IE.UTF-8 gl_ES.UTF-8 he_IL.UTF-8 \
        hi_IN.UTF-8 hr_HR.UTF-8 hu_HU.UTF-8 id_ID.UTF-8 it_CH.UTF-8 \
        it_IT.UTF-8 ja_JP.UTF-8 ko_KR.UTF-8 lt_LT.UTF-8 lv_LV.UTF-8 \
        mk_MK.UTF-8 ms_MY.UTF-8 mt_MT.UTF-8 nb_NO.UTF-8 nl_BE.UTF-8 \
        nl_NL.UTF-8 pl_PL.UTF-8 pt_BR.UTF-8 pt_PT.UTF-8 ro_RO.UTF-8 \
        ru_RU.UTF-8 sk_SK.UTF-8 sl_SI.UTF-8 sq_AL.UTF-8 sr_RS.UTF-8 \
        sv_FI.UTF-8 sv_SE.UTF-8 th_TH.UTF-8 tr_TR.UTF-8 uk_UA.UTF-8 \
        vi_VN.UTF-8 zh_CN.UTF-8 zh_HK.UTF-8 zh_TW.UTF-8)
    LOCALE=$(fuzzy_pick "Locale" "$locales" "${detected:-en_US.UTF-8}")
    info "Selected: $LOCALE" >&2
}

select_keymap() {
    echo "" >&2
    bold "Keyboard layout" >&2
    local detected
    detected=$(localectl status 2>/dev/null | awk '/X11 Layout/{print $3}' || echo "")
    is_placeholder "$detected" && detected=""
    local layouts
    layouts=$(localectl list-x11-keymap-layouts 2>/dev/null \
        || find /usr/share/X11/xkb/symbols -maxdepth 1 -type f \
            | xargs -I{} basename {} | sort)
    KEYMAP=$(fuzzy_pick "Keyboard layout" "$layouts" "${detected:-us}")
    info "Selected: $KEYMAP" >&2
}

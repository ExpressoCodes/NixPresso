# Shared helpers sourced by install.sh and update.sh.
# Not executable directly.

# fuzzy_pick LABEL ITEMS DEFAULT
# Live-filter picker: type to narrow the list, arrows to move, ENTER to select.
# Uses fzf when available; otherwise a built-in read-char loop.
fuzzy_pick() {
    local label="$1" items="$2" default="$3"

    # ── fzf path ──────────────────────────────────────────────────────────────
    if command -v fzf &>/dev/null; then
        local result
        result=$(printf '%s\n' "$items" | fzf --height=40% --reverse \
            --prompt="$label > " --query="$default" --select-1 --exit-0 2>/dev/null) \
            && { echo "$result"; return; }
        # ESC/Ctrl-C — fall through to built-in picker
    fi

    # ── built-in live-filter picker ───────────────────────────────────────────
    # Reads one character at a time; redraws a filtered list after each keypress.
    local query="$default"
    local selected=0  # 0-indexed cursor into filtered list

    # Hide cursor, enable raw input
    tput civis 2>/dev/null || true
    # Restore terminal on exit
    _fuzzy_cleanup() { tput cnorm 2>/dev/null || true; stty sane 2>/dev/null || true; }
    trap _fuzzy_cleanup RETURN INT TERM

    stty -echo -icanon min 1 time 0 2>/dev/null

    local LINES_DRAWN=0

    while true; do
        # Build filtered list
        local filtered
        if [ -z "$query" ]; then
            filtered=$(printf '%s\n' "$items")
        else
            filtered=$(printf '%s\n' "$items" | grep -i "$query" || true)
        fi

        local total
        total=$(printf '%s\n' "$filtered" | grep -c '' 2>/dev/null || echo 0)
        [ -z "$filtered" ] && total=0

        # Clamp cursor
        [ "$selected" -ge "$total" ] && selected=$(( total > 0 ? total - 1 : 0 ))
        [ "$selected" -lt 0 ] && selected=0

        # Erase previously drawn lines
        local i
        for (( i=0; i<LINES_DRAWN; i++ )); do
            printf '\033[A\033[2K'
        done
        LINES_DRAWN=0

        # Header
        printf "  \033[1m%s\033[0m > %s\n" "$label" "$query"
        (( LINES_DRAWN++ ))

        if [ "$total" -eq 0 ]; then
            printf "  \033[33mno matches\033[0m\n"
            (( LINES_DRAWN++ ))
        else
            local show=10
            local start=$(( selected > show/2 ? selected - show/2 : 0 ))
            [ $(( start + show )) -gt "$total" ] && start=$(( total - show > 0 ? total - show : 0 ))
            local end=$(( start + show < total ? start + show : total ))
            local idx
            for (( idx=start; idx<end; idx++ )); do
                local line
                line=$(printf '%s\n' "$filtered" | sed -n "$(( idx+1 ))p")
                if [ "$idx" -eq "$selected" ]; then
                    printf "  \033[7m %s \033[0m\n" "$line"
                else
                    printf "   %s\n" "$line"
                fi
                (( LINES_DRAWN++ ))
            done
            [ "$total" -gt "$show" ] && {
                printf "  \033[2m(%d more — keep typing to narrow)\033[0m\n" $(( total - show ))
                (( LINES_DRAWN++ ))
            }
        fi
        printf "  \033[2mENTER=select  ↑↓=move  BACKSPACE=erase  ESC=use default (%s)\033[0m\n" "$default"
        (( LINES_DRAWN++ ))

        # Read one char (or escape sequence)
        local ch esc
        IFS= read -r -d '' -n1 ch
        if [ "$ch" = $'\x1b' ]; then
            IFS= read -r -d '' -n1 -t 0.05 esc || true
            if [ "$esc" = '[' ]; then
                IFS= read -r -d '' -n1 -t 0.05 esc || true
                case "$esc" in
                    A) (( selected-- )) ;;   # up
                    B) (( selected++ )) ;;   # down
                esac
            else
                # bare ESC — use default
                _fuzzy_cleanup
                printf '\n'
                echo "$default"; return
            fi
        elif [ "$ch" = $'\x7f' ] || [ "$ch" = $'\b' ]; then
            query="${query%?}"
            selected=0
        elif [ "$ch" = $'\n' ] || [ "$ch" = $'\r' ] || [ -z "$ch" ]; then
            _fuzzy_cleanup
            printf '\n'
            if [ "$total" -gt 0 ]; then
                printf '%s\n' "$filtered" | sed -n "$(( selected+1 ))p"
            else
                echo "$default"
            fi
            return
        elif [[ "$ch" =~ [[:print:]] ]]; then
            query+="$ch"
            selected=0
        fi
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

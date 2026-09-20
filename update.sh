#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
VARS_FILE="/etc/nixos/.dotfiles-vars"
HOME_STATE_DIR="$HOME/.local/share/dotfiles-home-state"

# ── Helpers ───────────────────────────────────────────────────────────────────
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
info()  { printf '  %s\n' "$*"; }
ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; }
skip()  { printf '  \033[33m–\033[0m %s\n' "$*"; }

fuzzy_pick() {
    local label="$1" items="$2" default="$3"
    if command -v fzf &>/dev/null; then
        local result
        result=$(printf '%s\n' "$items" | fzf --height=40% --reverse \
            --prompt="$label > " --query="$default" --select-1 --exit-0 2>/dev/null) \
            && { echo "$result"; return; }
    fi
    local query results count choice
    while true; do
        printf "  \033[1m%s\033[0m (ENTER=use default '%s', or type to search): " "$label" "$default" >&2
        read -r query
        if [ -z "$query" ]; then echo "$default"; return; fi
        results=$(printf '%s\n' "$items" | grep -i "$query" || true)
        if [ -z "$results" ]; then printf '  No matches for "%s" — try again.\n' "$query" >&2; continue; fi
        count=$(printf '%s\n' "$results" | wc -l)
        if [ "$count" -eq 1 ]; then printf '%s\n' "$results"; return; fi
        if [ "$count" -gt 20 ]; then
            printf '  %d matches — showing first 20.\n' "$count" >&2
            results=$(printf '%s\n' "$results" | head -20); count=20
        fi
        local i=1
        while IFS= read -r line; do printf "  %2d)  %s\n" "$i" "$line" >&2; (( i++ )); done <<< "$results"
        printf "  Pick 1–%d, or ENTER to search again: " "$count" >&2
        read -r choice
        [ -z "$choice" ] && continue
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
            printf '%s\n' "$results" | sed -n "${choice}p"; return
        fi
        printf '  Invalid — enter a number 1–%d.\n' "$count" >&2
    done
}

is_placeholder() { [[ "$1" == your* ]]; }

select_timezone() {
    echo "" >&2; bold "Timezone" >&2
    local detected
    detected=$(timedatectl show --property=Timezone --value 2>/dev/null \
        || cat /etc/timezone 2>/dev/null \
        || readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||' || echo "")
    is_placeholder "$detected" && detected=""
    local zones
    zones=$(timedatectl list-timezones 2>/dev/null \
        || find /usr/share/zoneinfo -type f ! -name '*.tab' ! -name '*.list' \
            | sed 's|.*/zoneinfo/||' | sort)
    TIMEZONE=$(fuzzy_pick "Timezone" "$zones" "${detected:-UTC}")
    info "Selected: $TIMEZONE"
}

select_locale() {
    echo "" >&2; bold "Locale" >&2
    local detected
    detected=$(localectl status 2>/dev/null | awk '/System Locale/{print $3}' | cut -d= -f2 || echo "")
    is_placeholder "$detected" && detected=""
    [ -z "$detected" ] && detected="${LANG:-}"
    is_placeholder "$detected" && detected=""
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
    echo "" >&2; bold "Keyboard layout" >&2
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

merge_packages() {
    local base_file="$1" upstream_file="$2" current_file="$3"

    # 3-way merge: respect both upstream changes and user changes
    local result
    result=$(jq -n \
        --argjson base     "$(sudo cat "$base_file")" \
        --argjson upstream "$(cat "$upstream_file")" \
        --argjson current  "$(sudo cat "$current_file")" \
        '
          ($upstream - $base)    as $added_upstream   |
          ($base - $upstream)    as $removed_upstream |
          ($current - $base)     as $user_added       |
          ($current + $added_upstream - $removed_upstream) | unique | sort
        ')

    # Compute what changed for the summary
    local added removed user_kept
    added=$(jq -n \
        --argjson base "$(sudo cat "$base_file")" \
        --argjson upstream "$(cat "$upstream_file")" \
        '$upstream - $base | sort')
    removed=$(jq -n \
        --argjson base "$(sudo cat "$base_file")" \
        --argjson upstream "$(cat "$upstream_file")" \
        --argjson current "$(sudo cat "$current_file")" \
        '($base - $upstream) | map(select(. as $p | $current | contains([$p]))) | sort')
    user_kept=$(jq -n \
        --argjson base "$(sudo cat "$base_file")" \
        --argjson current "$(sudo cat "$current_file")" \
        '$current - $base | sort')

    local n_added n_removed n_user
    n_added=$(echo "$added" | jq 'length')
    n_removed=$(echo "$removed" | jq 'length')
    n_user=$(echo "$user_kept" | jq 'length')

    if [ "$n_added" -eq 0 ] && [ "$n_removed" -eq 0 ]; then
        echo "$result"
        return 0
    fi

    echo ""
    bold "  packages.json — upstream changes:"
    [ "$n_added"   -gt 0 ] && info "  + added:   $(echo "$added"   | jq -r 'join(", ")')"
    [ "$n_removed" -gt 0 ] && info "  - removed: $(echo "$removed" | jq -r 'join(", ")')"
    [ "$n_user"    -gt 0 ] && info "  ✓ your packages kept: $(echo "$user_kept" | jq -r 'join(", ")')"
    echo ""
    if [[ "${NIXSTORE_NONINTERACTIVE:-0}" = "1" ]]; then
        echo "$result"
        return 0
    fi
    read -rp "  $(bold "Apply these upstream changes?") [Y/n]: " ans
    ans="${ans:-y}"
    if [[ "$ans" =~ ^[Yy] ]]; then
        echo "$result"
    else
        sudo cat "$current_file"   # return unchanged
    fi
}

pci_to_nix() {
    local raw="${1%%.*}"
    local bus="${raw%%:*}"
    local slot="${raw##*:}"
    printf "PCI:%d:%d:0" "$((16#$bus))" "$((16#$slot))"
}

# ── Pull latest ───────────────────────────────────────────────────────────────
if [[ "${1:-}" != "--no-pull" ]] && [[ "${NIXSTORE_NO_PULL:-0}" != "1" ]]; then
    bold "→ Pulling latest changes ..."
    git -C "$DOTFILES" pull --ff-only
    echo ""
fi

# ── ~/.config + ~/.local/share (copied from dotfiles/home/) ──────────────────
bold "→ Syncing home config (~/.config, ~/.local/share) ..."

_is_text_file() {
    grep -qI '' "$1" 2>/dev/null
}

_backup_file() {
    local file="$1"
    local stamp
    stamp=$(date +%Y%m%d-%H%M%S)
    cp "$file" "${file}.bak.${stamp}"
    echo "${file}.bak.${stamp}"
}

_sync_home_file_interactive() {
    local src="$1" dst="$2" baseline="$3"

    echo ""
    bold "  ~/${dst#"$HOME"/} has upstream changes:"
    diff "$dst" "$src" | sed 's/^/    /' || true
    echo ""

    if [[ "${NIXSTORE_NONINTERACTIVE:-0}" = "1" ]]; then
        cp "$src" "$dst"
        cp "$src" "$baseline"
        ok "updated: ~/${dst#"$HOME"/}"
        return
    fi

    read -rp "  $(bold "[U]pdate / [S]kip") [u]: " ans </dev/tty
    ans="${ans:-u}"
    if [[ "$ans" =~ ^[Uu] ]]; then
        cp "$src" "$dst"
        cp "$src" "$baseline"
        ok "updated: ~/${dst#"$HOME"/}"
    else
        skip "kept local: ~/${dst#"$HOME"/}"
    fi
}

_sync_one_home_file() {
    local src="$1"
    local src_base="$2"
    local dst_base="$3"

    local rel dst baseline
    rel="${src#"$src_base"/}"
    dst="$dst_base/$rel"
    baseline="$HOME_STATE_DIR/${dst_base##"$HOME"/}/$rel"

    # Skip any stray .bak.* files in src (defensive)
    [[ "$src" =~ \.bak\.[0-9]{8}-[0-9]{6}$ ]] && return

    mkdir -p "$(dirname "$dst")"
    mkdir -p "$(dirname "$baseline")"

    # Case 1: destination does not exist yet
    if [ ! -f "$dst" ]; then
        cp "$src" "$dst"
        cp "$src" "$baseline"
        ok "new: ~/${dst#"$HOME"/}"
        return
    fi

    # Case 2: destination already matches new source
    if cmp -s "$src" "$dst"; then
        [ -f "$baseline" ] || cp "$src" "$baseline"
        skip "unchanged: ~/${dst#"$HOME"/}"
        return
    fi

    # Scripts: never merge, just back up + overwrite
    if [[ "$src" == *.sh ]]; then
        local bak
        bak=$(_backup_file "$dst")
        cp "$src" "$dst"
        cp "$src" "$baseline"
        ok "updated (script, backup: $(basename "$bak")): ~/${dst#"$HOME"/}"
        return
    fi

    # No baseline: first-run — show diff and ask (mirrors NixOS behaviour)
    if [ ! -f "$baseline" ]; then
        if ! _is_text_file "$src"; then
            # Binary, no baseline — apply silently
            cp "$src" "$dst"
            cp "$src" "$baseline"
            ok "updated (binary): ~/${dst#"$HOME"/}"
            return
        fi
        echo ""
        bold "  ~/${dst#"$HOME"/} differs from dotfiles:"
        diff "$dst" "$src" | sed 's/^/    /' || true
        echo ""
        if [[ "${NIXSTORE_NONINTERACTIVE:-0}" = "1" ]]; then
            cp "$src" "$dst"
            cp "$src" "$baseline"
            ok "updated: ~/${dst#"$HOME"/}"
            return
        fi
        read -rp "  $(bold "[U]pdate / [S]kip") [u]: " ans </dev/tty
        ans="${ans:-u}"
        if [[ "$ans" =~ ^[Uu] ]]; then
            cp "$src" "$dst"
            cp "$src" "$baseline"
            ok "updated: ~/${dst#"$HOME"/}"
        else
            cp "$src" "$baseline"
            skip "kept local (baseline recorded): ~/${dst#"$HOME"/}"
        fi
        return
    fi

    # Baseline matches new source: upstream unchanged, user may have diverged
    if cmp -s "$src" "$baseline"; then
        skip "unchanged upstream (user-modified): ~/${dst#"$HOME"/}"
        return
    fi

    # Binary files: back up + overwrite (can't merge)
    if ! _is_text_file "$src"; then
        local bak
        bak=$(_backup_file "$dst")
        cp "$src" "$dst"
        cp "$src" "$baseline"
        ok "updated (binary, backup: $(basename "$bak")): ~/${dst#"$HOME"/}"
        return
    fi

    # JSON files: use jq 3-way merge (like merge_packages)
    if [[ "$src" == *.json ]] && command -v jq &>/dev/null; then
        local merged
        merged=$(jq -n \
            --argjson base     "$(cat "$baseline")" \
            --argjson upstream "$(cat "$src")" \
            --argjson current  "$(cat "$dst")" \
            '
              ($upstream | to_entries) as $up_entries |
              ($base | to_entries) as $base_entries |
              ($current | to_entries) as $cur_entries |
              # Keys removed upstream
              ($base_entries | map(.key) | map(select(. as $k | ($up_entries | map(.key) | contains([$k]) | not)))) as $removed_keys |
              # Start with current, apply upstream additions/changes, remove upstream deletions
              reduce $up_entries[] as $e (
                $current;
                if ($base | has($e.key)) and (($base[$e.key]) == ($current[$e.key]))
                then . + {($e.key): $e.value}  # user did not change, take upstream
                else .  # user changed this key, keep user value
                end
              ) |
              del(.[$removed_keys[]])
            ' 2>/dev/null) || merged=""

        if [ -n "$merged" ] && echo "$merged" | jq . &>/dev/null; then
            if [ "$merged" = "$(cat "$dst")" ]; then
                cp "$src" "$baseline"
                skip "unchanged (json merge identical): ~/${dst#"$HOME"/}"
            else
                printf '%s\n' "$merged" > "$dst"
                cp "$src" "$baseline"
                ok "merged (json): ~/${dst#"$HOME"/}"
            fi
            return
        fi
        # jq merge failed — fall through to diff3
    fi

    # 3-way text merge with diff3
    if ! command -v diff3 &>/dev/null; then
        _sync_home_file_interactive "$src" "$dst" "$baseline"
        return
    fi

    local merged diff3_exit
    set +e
    merged=$(diff3 -m "$dst" "$baseline" "$src" 2>/dev/null)
    diff3_exit=$?
    set -e

    case "$diff3_exit" in
        0)
            if [ "$merged" = "$(cat "$dst")" ]; then
                cp "$src" "$baseline"
                skip "unchanged (merge identical): ~/${dst#"$HOME"/}"
            else
                printf '%s\n' "$merged" > "$dst"
                cp "$src" "$baseline"
                ok "merged: ~/${dst#"$HOME"/}"
            fi
            ;;
        1)
            local bak
            bak=$(_backup_file "$dst")
            cp "$src" "$dst"
            cp "$src" "$baseline"
            printf '  \033[33m!\033[0m conflict in ~/%s — backup: %s\n' \
                "${dst#"$HOME"/}" "$(basename "$bak")"
            printf '    Review and re-apply your customizations from the backup.\n'
            ;;
        *)
            _sync_home_file_interactive "$src" "$dst" "$baseline"
            ;;
    esac
}

_sync_home_files() {
    local src_base="$1"
    local dst_base="$2"

    [ -d "$src_base" ] || return 0

    while IFS= read -r -d '' src; do
        _sync_one_home_file "$src" "$src_base" "$dst_base"
    done < <(find "$src_base" -type f -print0)
}

_sync_home_files "$DOTFILES/home/.config"      "$HOME/.config"
_sync_home_files "$DOTFILES/home/.local/share" "$HOME/.local/share"
_sync_home_files "$DOTFILES/home/.local/bin"   "$HOME/.local/bin"
[ -d "$HOME/.local/bin" ] && chmod +x "$HOME/.local/bin"/* 2>/dev/null || true
echo ""

# ── dconf settings ────────────────────────────────────────────────────────────
DCONF_SCRIPT="$DOTFILES/home/apply-dconf.sh"
if [ -f "$DCONF_SCRIPT" ] && command -v dconf &>/dev/null; then
    bold "→ Applying dconf settings ..."
    bash "$DCONF_SCRIPT" && ok "dconf settings applied" || info "dconf: failed (try running ~/apply-dconf.sh manually)"
fi
echo ""

# ── NixOS config ──────────────────────────────────────────────────────────────
if [ ! -d /etc/nixos ]; then
    info "/etc/nixos not found — skipping NixOS update."
    exit 0
fi

if [ ! -f "$VARS_FILE" ]; then
    if [[ "${NIXSTORE_NONINTERACTIVE:-0}" = "1" ]]; then
        info "No $VARS_FILE found — run install.sh first."
        exit 1
    fi
    bold "No $VARS_FILE found — creating it now ..."
    echo ""

    read -rp "$(bold "Hostname") [$(hostname 2>/dev/null || echo nixos)]: " _hn
    _hn="${_hn:-$(hostname 2>/dev/null || echo nixos)}"

    read -rp "$(bold "Username") [$(whoami)]: " _un
    _un="${_un:-$(whoami)}"

    # GPU detection (reuse install.sh logic)
    _detected="unknown"
    if systemd-detect-virt --vm -q 2>/dev/null; then
        _detected="vm"
    else
        _pci=$(lspci 2>/dev/null || true)
        echo "$_pci" | grep -qi 'Virtio.*GPU\|VirtIO\|QXL paravirtual\|VMware SVGA\|VirtualBox Graph' && _detected="vm"
        if [ "$_detected" != "vm" ]; then
            _has_intel=false; _has_amd=false; _has_nvidia=false
            echo "$_pci" | grep -qi 'VGA.*Intel\|Intel.*VGA\|Intel.*Graphics' && _has_intel=true
            echo "$_pci" | grep -qi 'VGA.*AMD\|AMD.*VGA\|VGA.*ATI\|Radeon'   && _has_amd=true
            echo "$_pci" | grep -qi 'VGA.*NVIDIA\|NVIDIA.*VGA'                && _has_nvidia=true
            if $_has_intel && $_has_nvidia; then _detected="intel-nvidia"
            elif $_has_amd && $_has_nvidia;  then _detected="amd-nvidia"
            elif $_has_nvidia;               then _detected="nvidia"
            elif $_has_amd;                  then _detected="amd"
            elif $_has_intel;                then _detected="intel"
            fi
        fi
    fi

    echo ""
    echo "  1) intel          (Intel iGPU only)"
    echo "  2) amd            (AMD iGPU/dGPU only)"
    echo "  3) nvidia         (NVIDIA only)"
    echo "  4) intel-nvidia   (Intel iGPU + NVIDIA dGPU, PRIME offload)"
    echo "  5) amd-nvidia     (AMD iGPU + NVIDIA dGPU, PRIME offload)"
    echo "  6) vm             (virtual machine)"
    echo ""
    info "Detected: $_detected"
    _map=( "" intel amd nvidia intel-nvidia amd-nvidia vm )
    _default_idx=1
    for _i in 1 2 3 4 5 6; do [ "${_map[$_i]}" = "$_detected" ] && _default_idx=$_i; done
    while true; do
        read -rp "$(bold "GPU choice") [$_default_idx]: " _choice
        _choice="${_choice:-$_default_idx}"
        [[ "$_choice" =~ ^[1-6]$ ]] && break
        info "Enter a number 1–6."
    done
    _gpu="${_map[$_choice]}"

    select_timezone; _tz="$TIMEZONE"
    select_keymap;   _km="$KEYMAP"
    select_locale;   _lc="$LOCALE"

    echo ""
    bold "→ Requesting sudo to write $VARS_FILE ..."
    sudo -v
    sudo tee "$VARS_FILE" > /dev/null <<VARSEOF
DOTFILES_HOSTNAME=$_hn
DOTFILES_USERNAME=$_un
DOTFILES_GPU_VARIANT=$_gpu
DOTFILES_TIMEZONE=$_tz
DOTFILES_KEYMAP=$_km
DOTFILES_LOCALE=$_lc
DOTFILES_REPO=$DOTFILES
VARSEOF
    sudo chmod 644 "$VARS_FILE"
    ok "Created $VARS_FILE"
    echo ""
fi

# Load saved values from install
# shellcheck source=/dev/null
source "$VARS_FILE"
HOSTNAME="$DOTFILES_HOSTNAME"
USERNAME="$DOTFILES_USERNAME"
GPU_VARIANT="$DOTFILES_GPU_VARIANT"
TIMEZONE="${DOTFILES_TIMEZONE:-}"
KEYMAP="${DOTFILES_KEYMAP:-}"
LOCALE="${DOTFILES_LOCALE:-}"

# Prompt for any vars missing from an older install, then persist them
_vars_dirty=0
if [ -z "$TIMEZONE" ]; then
    select_timezone
    _vars_dirty=1
fi
if [ -z "$KEYMAP" ]; then
    select_keymap
    _vars_dirty=1
fi
if [ -z "$LOCALE" ]; then
    select_locale
    _vars_dirty=1
fi
if [ "$_vars_dirty" -eq 1 ]; then
    sudo tee "$VARS_FILE" > /dev/null <<VARSEOF
DOTFILES_HOSTNAME=$HOSTNAME
DOTFILES_USERNAME=$USERNAME
DOTFILES_GPU_VARIANT=$GPU_VARIANT
DOTFILES_TIMEZONE=$TIMEZONE
DOTFILES_KEYMAP=$KEYMAP
DOTFILES_LOCALE=$LOCALE
DOTFILES_REPO=${DOTFILES_REPO:-$DOTFILES}
VARSEOF
    ok "saved new vars to $VARS_FILE"
fi

bold "→ Applying NixOS updates (hostname=$HOSTNAME, user=$USERNAME, gpu=$GPU_VARIANT) ..."
bold "→ Requesting sudo ..."
if [[ "${NIXSTORE_NONINTERACTIVE:-0}" = "1" ]]; then
    if [[ -n "${SUDO_ASKPASS:-}" ]]; then
        sudo -A true || { info "sudo: authentication failed."; exit 1; }
    else
        sudo -n true || { info "sudo: credentials not cached — run nixstore again."; exit 1; }
    fi
else
    sudo -v
fi
( while true; do sudo -n true; sleep 50; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

UPDATED=0

BASE_PKGS="/etc/nixos/.dotfiles-packages-base.json"

for src in "$DOTFILES/nixos"/*; do
    [ -f "$src" ] || continue
    fname="$(basename "$src")"
    dest="/etc/nixos/$fname"

    # flake.lock is managed by `nix flake update`, not by dotfiles sync
    if [ "$fname" = "flake.lock" ]; then
        skip "skipped: flake.lock (managed by nix flake update)"
        continue
    fi

    # packages.json: 3-way merge to respect both upstream and user changes
    if [ "$fname" = "packages.json" ]; then
        if [ ! -f "$dest" ]; then
            sudo cp "$src" "$dest"
            sudo cp "$src" "$BASE_PKGS"
            ok "new: $fname"
            UPDATED=1
            continue
        fi

        if [ ! -f "$BASE_PKGS" ]; then
            # No baseline (pre-update.sh install) — fall through to generic diff
            info "no packages baseline found, treating packages.json as regular file"
        else
            new=$(merge_packages "$BASE_PKGS" "$src" "$dest")
            current=$(sudo cat "$dest")
            if [ "$new" = "$current" ]; then
                skip "unchanged: $fname"
            else
                echo "$new" | sudo tee "$dest" > /dev/null
                # Update baseline to current upstream so next run diffs correctly
                sudo cp "$src" "$BASE_PKGS"
                ok "merged: $fname"
                UPDATED=1
            fi
            continue
        fi
    fi

    # All other files: generate substituted version and diff
    new=$(sed \
        -e "s/yourhostname/$HOSTNAME/g" \
        -e "s/yourusername/$USERNAME/g" \
        -e "s|yourtimezone|$TIMEZONE|g" \
        -e "s/yourkbdlayout/$KEYMAP/g" \
        -e "s|yourlocale|$LOCALE|g" \
        "$src")

    if [ ! -f "$dest" ]; then
        echo "$new" | sudo tee "$dest" > /dev/null
        ok "new: $fname"
        UPDATED=1
        continue
    fi

    current=$(sudo cat "$dest")
    if [ "$new" = "$current" ]; then
        skip "unchanged: $fname"
        continue
    fi

    # Auto-apply when the current file still has unsubstituted placeholder tokens —
    # this is a first-run migration, not a real conflict.
    if grep -qE '\byour(hostname|username|timezone|kbdlayout|locale)\b' <(echo "$current"); then
        echo "$new" | sudo tee "$dest" > /dev/null
        ok "applied: $fname (substituted placeholder tokens)"
        UPDATED=1
        continue
    fi

    # File differs — show diff and ask
    echo ""
    bold "  $fname has local differences:"
    diff <(echo "$current") <(echo "$new") | sed 's/^/    /' || true
    echo ""
    if [[ "${NIXSTORE_NONINTERACTIVE:-0}" = "1" ]]; then
        echo "$new" | sudo tee "$dest" > /dev/null
        ok "updated: $fname"
        UPDATED=1
        continue
    fi
    read -rp "  $(bold "[U]pdate / [S]kip") [u]: " ans
    ans="${ans:-u}"
    if [[ "$ans" =~ ^[Uu] ]]; then
        echo "$new" | sudo tee "$dest" > /dev/null
        ok "updated: $fname"
        UPDATED=1
    else
        skip "kept local: $fname"
    fi
done

# hardware-acceleration.nix — re-generate from GPU variant
src="$DOTFILES/nixos/gpu/$GPU_VARIANT.nix"
dest="/etc/nixos/hardware-acceleration.nix"
case "$GPU_VARIANT" in
    intel-nvidia)
        intel_raw=$(lspci | grep -i 'Intel.*VGA\|VGA.*Intel\|Intel.*Graphics' | awk '{print $1}' | head -1)
        nvidia_raw=$(lspci | grep -i 'NVIDIA.*VGA\|VGA.*NVIDIA' | awk '{print $1}' | head -1)
        new=$(sed \
            -e "s/INTEL_BUS_ID/$(pci_to_nix "$intel_raw")/g" \
            -e "s/NVIDIA_BUS_ID/$(pci_to_nix "$nvidia_raw")/g" \
            "$src")
        ;;
    amd-nvidia)
        amd_raw=$(lspci | grep -i 'AMD.*VGA\|VGA.*AMD\|Radeon' | awk '{print $1}' | head -1)
        nvidia_raw=$(lspci | grep -i 'NVIDIA.*VGA\|VGA.*NVIDIA' | awk '{print $1}' | head -1)
        new=$(sed \
            -e "s/AMD_BUS_ID/$(pci_to_nix "$amd_raw")/g" \
            -e "s/NVIDIA_BUS_ID/$(pci_to_nix "$nvidia_raw")/g" \
            "$src")
        ;;
    *)
        new=$(cat "$src")
        ;;
esac

current=$(sudo cat "$dest" 2>/dev/null || true)
if [ "$new" = "$current" ]; then
    skip "unchanged: hardware-acceleration.nix"
elif [ -n "$current" ]; then
    echo ""
    bold "  hardware-acceleration.nix has differences:"
    diff <(echo "$current") <(echo "$new") | sed 's/^/    /' || true
    echo ""
    if [[ "${NIXSTORE_NONINTERACTIVE:-0}" = "1" ]]; then
        echo "$new" | sudo tee "$dest" > /dev/null
        ok "updated: hardware-acceleration.nix"
        UPDATED=1
    else
        read -rp "  $(bold "[U]pdate / [S]kip") [u]: " ans
        ans="${ans:-u}"
        if [[ "$ans" =~ ^[Uu] ]]; then
            echo "$new" | sudo tee "$dest" > /dev/null
            ok "updated: hardware-acceleration.nix"
            UPDATED=1
        else
            skip "kept local: hardware-acceleration.nix"
        fi
    fi
else
    echo "$new" | sudo tee "$dest" > /dev/null
    ok "new: hardware-acceleration.nix"
    UPDATED=1
fi

echo ""
bold "→ Updating flake inputs ..."
sudo sh -c 'cd /etc/nixos && nix flake update' && ok "flake inputs updated" || info "flake update failed — continuing with current lock"
UPDATED=1

echo ""
bold "→ Running nixos-rebuild switch ..."
sudo nixos-rebuild switch --flake "/etc/nixos#$HOSTNAME"

if command -v flatpak &>/dev/null; then
    echo ""
    bold "→ Ensuring Flathub remote ..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
        && ok "Flathub remote ready" \
        || info "flatpak remote-add failed — run manually if needed"
fi

if command -v hyprctl &>/dev/null && hyprctl monitors &>/dev/null 2>&1; then
    echo ""
    bold "→ Reloading Hyprland config ..."
    sleep 2
    hyprctl reload && ok "Hyprland config reloaded" || info "hyprctl reload failed — reload manually with: hyprctl reload"
fi

echo ""
bold "Done!"

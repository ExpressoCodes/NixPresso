#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

# ── Helpers ───────────────────────────────────────────────────────────────────
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
info()  { printf '  %s\n' "$*"; }
ask() {
    local prompt="$1" default="$2" answer
    read -rp "$(bold "$prompt") [$default]: " answer
    echo "${answer:-$default}"
}

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
    layouts=$(localectl list-x11-keymap-layouts 2>/dev/null || true)
    if [ -z "$layouts" ]; then
        local xkb_dir
        xkb_dir=$(find /run/current-system/sw/share/X11/xkb/symbols \
            /usr/share/X11/xkb/symbols -maxdepth 0 -type d 2>/dev/null | head -1 || true)
        [ -n "$xkb_dir" ] && layouts=$(find "$xkb_dir" -maxdepth 1 -type f \
            | xargs -I{} basename {} | sort 2>/dev/null || true)
    fi
    KEYMAP=$(fuzzy_pick "Keyboard layout" "$layouts" "${detected:-us}")
    info "Selected: $KEYMAP"
}

detect_gpu() {
    # VM check first — systemd-detect-virt is authoritative; lspci is the fallback
    if systemd-detect-virt --vm -q 2>/dev/null; then echo "vm" && return; fi
    local pci
    pci=$(lspci 2>/dev/null || true)
    echo "$pci" | grep -qi 'Virtio.*GPU\|VirtIO\|QXL paravirtual\|VMware SVGA\|VirtualBox Graph' && echo "vm" && return

    local has_intel=false has_amd=false has_nvidia=false
    echo "$pci" | grep -qi 'VGA.*Intel\|Intel.*VGA\|Intel.*Graphics' && has_intel=true
    echo "$pci" | grep -qi 'VGA.*AMD\|AMD.*VGA\|VGA.*ATI\|Radeon'   && has_amd=true
    echo "$pci" | grep -qi 'VGA.*NVIDIA\|NVIDIA.*VGA'                && has_nvidia=true

    if $has_intel && $has_nvidia; then echo "intel-nvidia"
    elif $has_amd  && $has_nvidia; then echo "amd-nvidia"
    elif $has_nvidia;              then echo "nvidia"
    elif $has_amd;                 then echo "amd"
    elif $has_intel;               then echo "intel"
    else                                echo "unknown"
    fi
}

pci_to_nix() {
    # "00:02.0" → "PCI:0:2:0"
    local raw="${1%%.*}"
    [ -z "$raw" ] && { printf '\033[31mError:\033[0m could not detect GPU bus ID — check lspci output and re-run\n' >&2; exit 1; }
    local bus="${raw%%:*}"
    local slot="${raw##*:}"
    printf "PCI:%d:%d:0" "$((16#$bus))" "$((16#$slot))"
}

select_gpu() {
    local detected="$1"
    echo ""
    bold "GPU configuration"
    info "Detected: $detected"
    echo ""
    echo "  1) intel          (Intel iGPU only)"
    echo "  2) amd            (AMD iGPU/dGPU only)"
    echo "  3) nvidia         (NVIDIA only)"
    echo "  4) intel-nvidia   (Intel iGPU + NVIDIA dGPU, PRIME offload)"
    echo "  5) amd-nvidia     (AMD iGPU + NVIDIA dGPU, PRIME offload)"
    echo ""
    local map=( "" intel amd nvidia intel-nvidia amd-nvidia )
    local default_idx=1
    for i in 1 2 3 4 5; do
        [ "${map[$i]}" = "$detected" ] && default_idx=$i
    done
    local choice
    while true; do
        read -rp "$(bold "Choice") [$default_idx]: " choice
        choice="${choice:-$default_idx}"
        [[ "$choice" =~ ^[1-5]$ ]] && break
        info "Invalid choice '$choice' — enter a number 1–5."
    done
    GPU_VARIANT="${map[$choice]}"
}

write_gpu_nix() {
    local variant="$1" dest="/etc/nixos/hardware-acceleration.nix"
    local src="$DOTFILES/nixos/gpu/$variant.nix"
    case "$variant" in
        intel-nvidia)
            local intel_raw nvidia_raw
            intel_raw=$(lspci | grep -i 'Intel.*VGA\|VGA.*Intel\|Intel.*Graphics' | awk '{print $1}' | head -1)
            nvidia_raw=$(lspci | grep -i 'NVIDIA.*VGA\|VGA.*NVIDIA' | awk '{print $1}' | head -1)
            sudo sed \
                -e "s/INTEL_BUS_ID/$(pci_to_nix "$intel_raw")/g" \
                -e "s/NVIDIA_BUS_ID/$(pci_to_nix "$nvidia_raw")/g" \
                "$src" | sudo tee "$dest" > /dev/null
            info "Intel bus: $(pci_to_nix "$intel_raw")  NVIDIA bus: $(pci_to_nix "$nvidia_raw")"
            ;;
        amd-nvidia)
            local amd_raw nvidia_raw
            amd_raw=$(lspci | grep -i 'AMD.*VGA\|VGA.*AMD\|Radeon' | awk '{print $1}' | head -1)
            nvidia_raw=$(lspci | grep -i 'NVIDIA.*VGA\|VGA.*NVIDIA' | awk '{print $1}' | head -1)
            sudo sed \
                -e "s/AMD_BUS_ID/$(pci_to_nix "$amd_raw")/g" \
                -e "s/NVIDIA_BUS_ID/$(pci_to_nix "$nvidia_raw")/g" \
                "$src" | sudo tee "$dest" > /dev/null
            info "AMD bus: $(pci_to_nix "$amd_raw")  NVIDIA bus: $(pci_to_nix "$nvidia_raw")"
            ;;
        *)
            sudo cp "$src" "$dest"
            ;;
    esac
}

# ── Gather config ─────────────────────────────────────────────────────────────
echo ""
bold "── NixOS Dotfiles Installer ──────────────────────────────────────"
echo ""
HOSTNAME=$(ask "Hostname" "$(hostname 2>/dev/null || echo nixos)")
USERNAME=$(ask "Username" "$(whoami)")
select_timezone
select_keymap
select_locale

if [ -d /etc/nixos ]; then
    _detected="$(detect_gpu)"
    if [ "$_detected" = "vm" ]; then
        GPU_VARIANT="vm"
        bold "Virtual machine detected — configuring for virtio-gpu"
    else
        select_gpu "$_detected"
    fi
fi
echo ""

# ── Sudo ──────────────────────────────────────────────────────────────────────
if [ -d /etc/nixos ]; then
    bold "→ Requesting sudo for system steps ..."
    sudo -v
    ( while true; do sudo -n true; sleep 50; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
fi

# ── NixOS system config ───────────────────────────────────────────────────────
if [ -d /etc/nixos ]; then
    bold "→ Copying NixOS config to /etc/nixos/ ..."
    for src in "$DOTFILES/nixos"/*; do
        [ -f "$src" ] || continue   # skip subdirectories (nixos/gpu/)
        fname="$(basename "$src")"
        sudo sed \
            -e "s/yourhostname/$HOSTNAME/g" \
            -e "s/yourusername/$USERNAME/g" \
            -e "s|yourtimezone|$TIMEZONE|g" \
            -e "s/yourkbdlayout/$KEYMAP/g" \
            -e "s|yourlocale|$LOCALE|g" \
            "$src" | sudo tee "/etc/nixos/$fname" > /dev/null
        info "wrote /etc/nixos/$fname"
    done

    bold "→ Writing hardware-acceleration.nix ($GPU_VARIANT) ..."
    write_gpu_nix "$GPU_VARIANT"
    info "wrote /etc/nixos/hardware-acceleration.nix"

    # Save user values so update.sh can re-apply substitutions later
    sudo tee /etc/nixos/.dotfiles-vars > /dev/null <<EOF
DOTFILES_HOSTNAME=$HOSTNAME
DOTFILES_USERNAME=$USERNAME
DOTFILES_GPU_VARIANT=$GPU_VARIANT
DOTFILES_TIMEZONE=$TIMEZONE
DOTFILES_KEYMAP=$KEYMAP
DOTFILES_LOCALE=$LOCALE
DOTFILES_REPO=$DOTFILES
EOF
    sudo chmod 644 /etc/nixos/.dotfiles-vars   # readable by user services
    info "saved vars to /etc/nixos/.dotfiles-vars"

    # Save packages baseline so update.sh can 3-way merge future changes
    sudo cp "$DOTFILES/nixos/packages.json" /etc/nixos/.dotfiles-packages-base.json
    info "saved packages baseline to /etc/nixos/.dotfiles-packages-base.json"

    # Seed NixOS baseline so update.sh knows what was just installed
    sudo mkdir -p /etc/nixos/.dotfiles-nixos-baseline
    for src in "$DOTFILES/nixos"/*; do
        [ -f "$src" ] || continue
        fname="$(basename "$src")"
        [ "$fname" = "flake.lock" ] && continue
        sudo sed \
            -e "s/yourhostname/$HOSTNAME/g" \
            -e "s/yourusername/$USERNAME/g" \
            -e "s|yourtimezone|$TIMEZONE|g" \
            -e "s/yourkbdlayout/$KEYMAP/g" \
            -e "s|yourlocale|$LOCALE|g" \
            "$src" | sudo tee "/etc/nixos/.dotfiles-nixos-baseline/$fname" > /dev/null
    done
    # hardware-acceleration.nix baseline (already written to /etc/nixos/ by write_gpu_nix)
    sudo cp /etc/nixos/hardware-acceleration.nix /etc/nixos/.dotfiles-nixos-baseline/hardware-acceleration.nix 2>/dev/null || true
    info "seeded NixOS baseline in /etc/nixos/.dotfiles-nixos-baseline/"

    if [ ! -f /etc/nixos/hardware-configuration.nix ]; then
        bold "→ Generating hardware-configuration.nix ..."
        sudo nixos-generate-config
    else
        info "hardware-configuration.nix already present, skipping."
    fi

    bold "→ Setting hostname temporarily to '$HOSTNAME' ..."
    sudo hostname "$HOSTNAME"

    bold "→ Running nixos-rebuild switch ..."
    sudo nixos-rebuild switch --flake "/etc/nixos#$HOSTNAME"
else
    info "/etc/nixos not found — skipping NixOS system config."
fi

# ── User config (~/.config) ───────────────────────────────────────────────────
bold "→ Linking ~/.config entries for $USERNAME ..."
TARGET_HOME="/home/$USERNAME"
CONFIG="$TARGET_HOME/.config"

if [ "$(whoami)" != "$USERNAME" ]; then
    # Running as a different user (e.g. root or an installer account).
    # Use sudo throughout and fix ownership at the end.
    # Also pre-create the home dir: nixos-rebuild creates the account but the
    # home dir is only made on first login.
    if [ ! -d "$TARGET_HOME" ]; then
        sudo mkdir -p "$TARGET_HOME"
        sudo chown "$USERNAME:users" "$TARGET_HOME"
        info "created $TARGET_HOME"
    fi
    sudo mkdir -p "$CONFIG"
    for src in "$DOTFILES/home/.config"/*/; do
        name="$(basename "$src")"
        dst="$CONFIG/$name"
        if sudo test -e "$dst" && ! sudo test -L "$dst"; then
            info "backing up existing: $dst → $dst.bak"
            sudo mv "$dst" "$dst.bak"
        fi
        sudo ln -sfn "$src" "$dst"
        info "linked: $dst"
    done
    sudo chown -R "$USERNAME:users" "$CONFIG"

    bold "→ Linking ~/.local/share entries for $USERNAME ..."
    for src in "$DOTFILES/home/.local/share"/*/; do
        [ -d "$src" ] || continue
        rel="${src#$DOTFILES/home/}"   # e.g. .local/share/rofi
        dst="$TARGET_HOME/$rel"
        sudo mkdir -p "$(dirname "$dst")"
        if sudo test -e "$dst" && ! sudo test -L "$dst"; then
            info "backing up existing: $dst → $dst.bak"
            sudo mv "$dst" "$dst.bak"
        fi
        sudo ln -sfn "$src" "$dst"
        info "linked: $dst"
    done
    sudo chown -R "$USERNAME:users" "$TARGET_HOME/.local"

    bold "→ Linking ~/.local/bin entries for $USERNAME ..."
    local_bin_src="$DOTFILES/home/.local/bin"
    if [ -d "$local_bin_src" ]; then
        dst_bin="$TARGET_HOME/.local/bin"
        sudo mkdir -p "$dst_bin"
        for src in "$local_bin_src"/*; do
            [ -e "$src" ] || continue
            name="$(basename "$src")"
            dst="$dst_bin/$name"
            if sudo test -e "$dst" && ! sudo test -L "$dst"; then
                sudo mv "$dst" "$dst.bak"
            fi
            sudo ln -sfn "$src" "$dst"
            sudo chmod +x "$dst"
            info "linked: $dst"
        done
        sudo chown -R "$USERNAME:users" "$dst_bin"
    fi
else
    # Running as the target user — home already exists, no sudo needed,
    # no ownership changes required.
    mkdir -p "$CONFIG"
    for src in "$DOTFILES/home/.config"/*/; do
        name="$(basename "$src")"
        dst="$CONFIG/$name"
        if [ -e "$dst" ] && [ ! -L "$dst" ]; then
            info "backing up existing: $dst → $dst.bak"
            mv "$dst" "$dst.bak"
        fi
        ln -sfn "$src" "$dst"
        info "linked: $dst"
    done

    bold "→ Linking ~/.local/share entries ..."
    for src in "$DOTFILES/home/.local/share"/*/; do
        [ -d "$src" ] || continue
        rel="${src#$DOTFILES/home/}"   # e.g. .local/share/rofi
        dst="$TARGET_HOME/$rel"
        mkdir -p "$(dirname "$dst")"
        if [ -e "$dst" ] && [ ! -L "$dst" ]; then
            info "backing up existing: $dst → $dst.bak"
            mv "$dst" "$dst.bak"
        fi
        ln -sfn "$src" "$dst"
        info "linked: $dst"
    done

    bold "→ Linking ~/.local/bin entries ..."
    local_bin_src="$DOTFILES/home/.local/bin"
    if [ -d "$local_bin_src" ]; then
        dst_bin="$TARGET_HOME/.local/bin"
        mkdir -p "$dst_bin"
        for src in "$local_bin_src"/*; do
            [ -e "$src" ] || continue
            name="$(basename "$src")"
            dst="$dst_bin/$name"
            if [ -e "$dst" ] && [ ! -L "$dst" ]; then
                mv "$dst" "$dst.bak"
            fi
            ln -sfn "$src" "$dst"
            chmod +x "$dst"
            info "linked: $dst"
        done
    fi
fi

# ── dconf settings ────────────────────────────────────────────────────────────
if command -v dconf &>/dev/null; then
    bold "→ Applying dconf settings ..."
    cp "$DOTFILES/home/apply-dconf.sh" "$TARGET_HOME/apply-dconf.sh"
    chmod +x "$TARGET_HOME/apply-dconf.sh"
    if [ "$(whoami)" != "$USERNAME" ]; then
        sudo -u "$USERNAME" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$USERNAME")/bus" \
            bash "$TARGET_HOME/apply-dconf.sh" || info "dconf: session bus not available, run ~/apply-dconf.sh after login"
    else
        bash "$TARGET_HOME/apply-dconf.sh" || info "dconf: failed, run ~/apply-dconf.sh after login"
    fi
else
    info "dconf not found — skipping (run ~/apply-dconf.sh after first login if needed)"
fi

echo ""
bold "Done! Log out and back in (or reboot) for all changes to take effect."
bold "To receive future updates: ./update.sh"

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
    elif $has_intel; then
        [ "$(detect_intel_gpu_gen)" = "legacy" ] && echo "intel-legacy" || echo "intel"
    else                                echo "unknown"
    fi
}

detect_intel_gpu_gen() {
    # Returns "legacy" for Intel Gen 8 (Broadwell / 5th-gen Core) and older,
    # "modern" for Gen 9 (Skylake / 6th-gen Core) and newer.
    # Reads the two-byte hex prefix of the Intel iGPU PCI device ID:
    #   0x16xx = Broadwell (Gen 8) — iris has broken Wayland EGL on this hardware
    #   0x19xx and above = Skylake+ — iris works correctly
    local dev_id
    dev_id=$(lspci -n 2>/dev/null \
        | awk '/8086:/ && (/ 0300 | 0302 | 0380 /)' \
        | grep -oE '8086:[0-9a-fA-F]+' | cut -d: -f2 | head -1)
    [ -z "$dev_id" ] && { echo "modern"; return; }
    local hi
    hi=$(printf '%d' "0x${dev_id:0:2}" 2>/dev/null) || { echo "modern"; return; }
    # Skylake starts at prefix 0x19 (decimal 25); anything below is Gen 8 or older
    [ "$hi" -lt 25 ] && echo "legacy" || echo "modern"
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
    echo "  1) intel          (Intel iGPU, Gen 9 / Skylake and newer)"
    echo "  2) intel-legacy   (Intel iGPU, Gen 8 / Broadwell and older — uses crocus driver)"
    echo "  3) amd            (AMD iGPU/dGPU only)"
    echo "  4) nvidia         (NVIDIA only)"
    echo "  5) intel-nvidia   (Intel iGPU + NVIDIA dGPU, PRIME offload)"
    echo "  6) amd-nvidia     (AMD iGPU + NVIDIA dGPU, PRIME offload)"
    echo ""
    local map=( "" intel intel-legacy amd nvidia intel-nvidia amd-nvidia )
    local default_idx=1
    for i in 1 2 3 4 5 6; do
        [ "${map[$i]}" = "$detected" ] && default_idx=$i
    done
    local choice
    while true; do
        read -rp "$(bold "Choice") [$default_idx]: " choice
        choice="${choice:-$default_idx}"
        [[ "$choice" =~ ^[1-6]$ ]] && break
        info "Invalid choice '$choice' — enter a number 1–6."
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

patch_for_legacy_intel() {
    # Materialise a symlink (to file or dir) into a real local copy so we can
    # patch it without touching the dotfiles repo.
    _materialise() {
        local dst="$1" use_sudo="${2:-false}"
        local _sudo=""; $use_sudo && _sudo="sudo"
        if $_sudo test -L "$dst"; then
            local src; src=$(readlink -f "$dst")
            $_sudo rm "$dst"
            if $_sudo test -d "$src"; then
                $_sudo cp -rT "$src" "$dst"
            else
                $_sudo cp "$src" "$dst"
            fi
        fi
    }

    local config_dir="$1"   # e.g. /home/tommy/.config
    local bin_dir="$2"      # e.g. /home/tommy/.local/bin
    local use_sudo="${3:-false}"
    local _sudo=""; $use_sudo && _sudo="sudo"

    # ── Hyprland configs ──────────────────────────────────────────────────
    local hypr="$config_dir/hypr"
    _materialise "$hypr" "$use_sudo"

    # keybinds.lua: launch kitty via crocus
    $_sudo sed -i \
        's|local terminal    = "kitty"|local terminal    = "env MESA_LOADER_DRIVER_OVERRIDE=crocus kitty"|' \
        "$hypr/keybinds.lua"

    # hyprland.lua: launch Quickshell bar and dock via crocus
    $_sudo sed -i \
        's|hl\.exec_cmd("qs")|hl.exec_cmd("env MESA_LOADER_DRIVER_OVERRIDE=crocus qs")|' \
        "$hypr/hyprland.lua"
    $_sudo sed -i \
        's|hl\.exec_cmd("quickshell -p "|hl.exec_cmd("env MESA_LOADER_DRIVER_OVERRIDE=crocus quickshell -p "|' \
        "$hypr/hyprland.lua"

    # ── qs-restart helper ─────────────────────────────────────────────────
    local qs_restart="$bin_dir/qs-restart"
    _materialise "$qs_restart" "$use_sudo"
    $_sudo sed -i \
        's|^quickshell |env MESA_LOADER_DRIVER_OVERRIDE=crocus quickshell |' \
        "$qs_restart"

    info "Applied legacy-Intel crocus patches to Hyprland + Quickshell configs"
}

detect_boot_mode() {
    if [ -d /sys/firmware/efi ]; then
        echo "efi"
    else
        echo "bios"
    fi
}

detect_grub_device() {
    local root_src disk
    root_src=$(findmnt -n -o SOURCE / 2>/dev/null || echo "")
    # Strip btrfs subvolume notation, e.g. /dev/sda3[/@root] → /dev/sda3
    root_src="${root_src%%\[*}"
    if [ -b "$root_src" ]; then
        disk=$(lsblk -ndo pkname "$root_src" 2>/dev/null || true)
        if [ -n "$disk" ]; then
            echo "/dev/$disk"
            return
        fi
    fi
    # Fallback: strip trailing partition digit(s) from the path
    echo "$root_src" | sed 's/[0-9]*$//'
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
    bold "→ Adding NixOS unstable channels ..."
    sudo nix-channel --add https://nixos.org/channels/nixos-unstable nixos
    sudo nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs
    sudo nix-channel --update
    info "channels: nixos → nixos-unstable, nixpkgs → nixpkgs-unstable"

    BOOT_MODE=$(detect_boot_mode)
    GRUB_DEVICE=""
    if [ "$BOOT_MODE" = "bios" ]; then
        GRUB_DEVICE=$(detect_grub_device)
        info "BIOS/MBR system — GRUB device: $GRUB_DEVICE"
    else
        info "EFI system — using systemd-boot"
    fi
    EFI_BOOL="false"; [ "$BOOT_MODE" = "efi" ] && EFI_BOOL="true"

    bold "→ Copying NixOS config to /etc/nixos/ ..."
    for src in "$DOTFILES/nixos"/*; do
        [ -f "$src" ] || continue   # skip subdirectories (nixos/gpu/)
        fname="$(basename "$src")"
        if [ "$fname" = "boot.nix" ]; then
            sudo sed \
                -e "s/yourhostname/$HOSTNAME/g" \
                -e "s/yourusername/$USERNAME/g" \
                -e "s|yourtimezone|$TIMEZONE|g" \
                -e "s/yourkbdlayout/$KEYMAP/g" \
                -e "s|yourlocale|$LOCALE|g" \
                -e "s/YOUREFIMODE/$EFI_BOOL/g" \
                -e "s|YOURGRUBDEVICE|$GRUB_DEVICE|g" \
                "$src" | sudo tee "/etc/nixos/$fname" > /dev/null
        else
            sudo sed \
                -e "s/yourhostname/$HOSTNAME/g" \
                -e "s/yourusername/$USERNAME/g" \
                -e "s|yourtimezone|$TIMEZONE|g" \
                -e "s/yourkbdlayout/$KEYMAP/g" \
                -e "s|yourlocale|$LOCALE|g" \
                "$src" | sudo tee "/etc/nixos/$fname" > /dev/null
        fi
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
DOTFILES_BOOT_MODE=$BOOT_MODE
DOTFILES_GRUB_DEVICE=${GRUB_DEVICE:-}
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
        if [ "$fname" = "boot.nix" ]; then
            sudo sed \
                -e "s/yourhostname/$HOSTNAME/g" \
                -e "s/yourusername/$USERNAME/g" \
                -e "s|yourtimezone|$TIMEZONE|g" \
                -e "s/yourkbdlayout/$KEYMAP/g" \
                -e "s|yourlocale|$LOCALE|g" \
                -e "s/YOUREFIMODE/$EFI_BOOL/g" \
                -e "s|YOURGRUBDEVICE|$GRUB_DEVICE|g" \
                "$src" | sudo tee "/etc/nixos/.dotfiles-nixos-baseline/$fname" > /dev/null
        else
            sudo sed \
                -e "s/yourhostname/$HOSTNAME/g" \
                -e "s/yourusername/$USERNAME/g" \
                -e "s|yourtimezone|$TIMEZONE|g" \
                -e "s/yourkbdlayout/$KEYMAP/g" \
                -e "s|yourlocale|$LOCALE|g" \
                "$src" | sudo tee "/etc/nixos/.dotfiles-nixos-baseline/$fname" > /dev/null
        fi
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

    # ── Two-phase build: seed Hyprland cache before building Hyprland ────────
    # Phase 1 configures the nix daemon with the Hyprland substituter without
    # building Hyprland itself.  Phase 2 can then pull from cache instead of
    # compiling from source.
    bold "→ Phase 1: bootstrap build (registers Hyprland cache, no Hyprland yet) ..."
    sudo tee /etc/nixos/cachix-bootstrap.nix > /dev/null <<'CACHIX_EOF'
{ ... }:
{
  nix.settings = {
    substituters        = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
  };
}
CACHIX_EOF
    sudo sed -i 's|./hyprland.nix|./cachix-bootstrap.nix|' /etc/nixos/configuration.nix
    sudo nixos-rebuild switch --flake "/etc/nixos#$HOSTNAME"

    bold "→ Phase 2: full build with Hyprland (pulling from cache) ..."
    sudo sed -i 's|./cachix-bootstrap.nix|./hyprland.nix|' /etc/nixos/configuration.nix
    sudo rm /etc/nixos/cachix-bootstrap.nix
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

    bold "→ Copying ~/.local/share entries for $USERNAME ..."
    for src in "$DOTFILES/home/.local/share"/*/; do
        [ -d "$src" ] || continue
        rel="${src#$DOTFILES/home/}"
        rel="${rel%/}"
        dst="$TARGET_HOME/$rel"
        sudo mkdir -p "$(dirname "$dst")"
        if sudo test -L "$dst"; then
            sudo rm "$dst"
        elif sudo test -d "$dst"; then
            info "backing up existing: $dst → $dst.bak"
            sudo mv "$dst" "$dst.bak"
        fi
        sudo cp -rT "$src" "$dst"
        info "copied: $dst"
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
    if [ "$GPU_VARIANT" = "intel-legacy" ]; then
        patch_for_legacy_intel "$CONFIG" "$TARGET_HOME/.local/bin" true
        sudo chown -R "$USERNAME:users" "$CONFIG/hypr" "$TARGET_HOME/.local/bin/qs-restart" 2>/dev/null || true
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

    bold "→ Copying ~/.local/share entries ..."
    for src in "$DOTFILES/home/.local/share"/*/; do
        [ -d "$src" ] || continue
        rel="${src#$DOTFILES/home/}"
        rel="${rel%/}"
        dst="$TARGET_HOME/$rel"
        mkdir -p "$(dirname "$dst")"
        if [ -L "$dst" ]; then
            rm "$dst"
        elif [ -d "$dst" ]; then
            info "backing up existing: $dst → $dst.bak"
            mv "$dst" "$dst.bak"
        fi
        cp -rT "$src" "$dst"
        info "copied: $dst"
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
    if [ "$GPU_VARIANT" = "intel-legacy" ]; then
        patch_for_legacy_intel "$CONFIG" "$TARGET_HOME/.local/bin" false
    fi
fi

# ── dconf settings ────────────────────────────────────────────────────────────
if command -v dconf &>/dev/null; then
    bold "→ Applying dconf settings ..."
    if [ "$(whoami)" != "$USERNAME" ]; then
        sudo -u "$USERNAME" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$USERNAME")/bus" \
            bash "$DOTFILES/home/apply-dconf.sh" \
            || info "dconf: session bus not available — run '$DOTFILES/home/apply-dconf.sh' after login"
    else
        bash "$DOTFILES/home/apply-dconf.sh" \
            || info "dconf: failed — run '$DOTFILES/home/apply-dconf.sh' after login"
    fi
else
    info "dconf not found — skipping (run '$DOTFILES/home/apply-dconf.sh' after first login if needed)"
fi

if command -v hyprctl &>/dev/null && hyprctl monitors &>/dev/null 2>&1; then
    init_monitors="$HOME/.config/hypr/scripts/init-monitors.sh"
    if [ -f "$init_monitors" ]; then
        echo ""
        bold "→ Detecting monitors ..."
        bash "$init_monitors" && bold "monitors.lua updated" || info "init-monitors.sh failed — skipping"
    fi
fi

# ── Wallpapers ────────────────────────────────────────────────────────────────
if [ -d "$DOTFILES/wallpapers" ]; then
    bold "→ Installing wallpapers to ~/Pictures/Wallpapers/ ..."
    mkdir -p ~/Pictures/Wallpapers
    _wp_copied=0
    for _f in "$DOTFILES/wallpapers"/*; do
        [ -f "$_f" ] || continue
        if cp -n "$_f" ~/Pictures/Wallpapers/ 2>/dev/null; then
            _wp_copied=$((_wp_copied + 1))
        fi
    done
    info "Copied $_wp_copied wallpaper(s) to ~/Pictures/Wallpapers/"
fi

echo ""
bold "Done! Log out and back in (or reboot) for all changes to take effect."
bold "To receive future updates: ./update.sh"

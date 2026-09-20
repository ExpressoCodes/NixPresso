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

# fuzzy_pick LABEL ITEMS DEFAULT
# Uses fzf when available; falls back to a grep+numbered-list picker.
fuzzy_pick() {
    local label="$1" items="$2" default="$3"
    if command -v fzf &>/dev/null; then
        local result
        result=$(printf '%s\n' "$items" | fzf --height=40% --reverse \
            --prompt="$label: " --query="$default" --select-1 --exit-0 2>/dev/null) \
            && echo "$result" && return
        # fzf aborted (ESC/Ctrl-C) — fall through to manual
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

select_timezone() {
    echo ""
    bold "Timezone"
    local detected
    detected=$(timedatectl show --property=Timezone --value 2>/dev/null \
        || cat /etc/timezone 2>/dev/null \
        || readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||' \
        || echo "UTC")
    local zones
    zones=$(timedatectl list-timezones 2>/dev/null \
        || find /usr/share/zoneinfo -type f ! -name '*.tab' ! -name '*.list' \
            | sed 's|.*/zoneinfo/||' | sort)
    TIMEZONE=$(fuzzy_pick "Timezone" "$zones" "$detected")
    info "Selected: $TIMEZONE"
}

select_keymap() {
    echo ""
    bold "Keyboard layout"
    local detected
    detected=$(localectl status 2>/dev/null | awk '/X11 Layout/{print $3}' \
        || localectl status 2>/dev/null | awk '/VC Keymap/{print $3}' \
        || echo "us")
    local layouts
    layouts=$(localectl list-x11-keymap-layouts 2>/dev/null \
        || find /usr/share/X11/xkb/symbols -maxdepth 1 -type f \
            | xargs -I{} basename {} | sort)
    KEYMAP=$(fuzzy_pick "Keyboard layout" "$layouts" "$detected")
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
            -e "s/yourtimezone/$TIMEZONE/g" \
            -e "s/yourkbdlayout/$KEYMAP/g" \
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
DOTFILES_REPO=$DOTFILES
EOF
    sudo chmod 644 /etc/nixos/.dotfiles-vars   # readable by user services
    info "saved vars to /etc/nixos/.dotfiles-vars"

    # Save packages baseline so update.sh can 3-way merge future changes
    sudo cp "$DOTFILES/nixos/packages.json" /etc/nixos/.dotfiles-packages-base.json
    info "saved packages baseline to /etc/nixos/.dotfiles-packages-base.json"

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

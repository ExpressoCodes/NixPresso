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

# ── Gather config ─────────────────────────────────────────────────────────────
echo ""
bold "── NixOS Dotfiles Installer ──────────────────────────────────────"
echo ""
HOSTNAME=$(ask "Hostname" "$(hostname 2>/dev/null || echo nixos)")
USERNAME=$(ask "Username" "$(whoami)")

if [ -d /etc/nixos ]; then
    select_gpu "$(detect_gpu)"
fi
echo ""

# ── GPU detection ─────────────────────────────────────────────────────────────
detect_gpu() {
    local pci
    pci=$(lspci 2>/dev/null || true)
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
    local raw="${1%%.*}"   # strip function suffix
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
    read -rp "$(bold "Choice") [$default_idx]: " choice
    choice="${choice:-$default_idx}"
    GPU_VARIANT="${map[$choice]:-intel}"
}

# ── Sudo ──────────────────────────────────────────────────────────────────────
if [ -d /etc/nixos ]; then
    bold "→ Requesting sudo for system steps ..."
    sudo -v
    # Keep sudo alive for the duration of the script (nixos-rebuild can be slow)
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
            "$src" | sudo tee "/etc/nixos/$fname" > /dev/null
        info "wrote /etc/nixos/$fname"
    done

    # Write hardware-acceleration.nix from the selected GPU variant,
    # substituting PCI bus IDs for hybrid (PRIME) configs.
    bold "→ Writing hardware-acceleration.nix ($GPU_VARIANT) ..."
    GPU_SRC="$DOTFILES/nixos/gpu/$GPU_VARIANT.nix"
    case "$GPU_VARIANT" in
        intel-nvidia)
            INTEL_BUS=$(lspci | grep -i 'Intel.*VGA\|VGA.*Intel\|Intel.*Graphics' | awk '{print $1}' | head -1)
            NVIDIA_BUS=$(lspci | grep -i 'NVIDIA.*VGA\|VGA.*NVIDIA' | awk '{print $1}' | head -1)
            sudo sed \
                -e "s/INTEL_BUS_ID/$(pci_to_nix "$INTEL_BUS")/g" \
                -e "s/NVIDIA_BUS_ID/$(pci_to_nix "$NVIDIA_BUS")/g" \
                "$GPU_SRC" | sudo tee /etc/nixos/hardware-acceleration.nix > /dev/null
            info "Intel bus: $(pci_to_nix "$INTEL_BUS")  NVIDIA bus: $(pci_to_nix "$NVIDIA_BUS")"
            ;;
        amd-nvidia)
            AMD_BUS=$(lspci | grep -i 'AMD.*VGA\|VGA.*AMD\|Radeon' | awk '{print $1}' | head -1)
            NVIDIA_BUS=$(lspci | grep -i 'NVIDIA.*VGA\|VGA.*NVIDIA' | awk '{print $1}' | head -1)
            sudo sed \
                -e "s/AMD_BUS_ID/$(pci_to_nix "$AMD_BUS")/g" \
                -e "s/NVIDIA_BUS_ID/$(pci_to_nix "$NVIDIA_BUS")/g" \
                "$GPU_SRC" | sudo tee /etc/nixos/hardware-acceleration.nix > /dev/null
            info "AMD bus: $(pci_to_nix "$AMD_BUS")  NVIDIA bus: $(pci_to_nix "$NVIDIA_BUS")"
            ;;
        *)
            sudo cp "$GPU_SRC" /etc/nixos/hardware-acceleration.nix
            ;;
    esac
    info "wrote /etc/nixos/hardware-acceleration.nix"

    # Generate hardware-configuration.nix if absent.
    # nixos-generate-config won't overwrite an existing configuration.nix,
    # so it's safe to run after we've written our files.
    if [ ! -f /etc/nixos/hardware-configuration.nix ]; then
        bold "→ Generating hardware-configuration.nix ..."
        sudo nixos-generate-config
    else
        info "hardware-configuration.nix already present, skipping."
    fi

    # Set hostname temporarily so the flake attribute nixosConfigurations.<hostname>
    # is reachable without a reboot.
    bold "→ Setting hostname temporarily to '$HOSTNAME' ..."
    sudo hostname "$HOSTNAME"

    bold "→ Running nixos-rebuild switch ..."
    sudo nixos-rebuild switch --flake "/etc/nixos#$HOSTNAME"
else
    info "/etc/nixos not found — skipping NixOS system config."
fi

# ── User config (~/.config) ───────────────────────────────────────────────────
bold "→ Linking ~/.config entries ..."
CONFIG="$HOME/.config"
for src in "$DOTFILES/home/.config"/*/; do
    name="$(basename "$src")"
    dst="$CONFIG/$name"
    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        info "backing up existing: $dst → $dst.bak"
        mv "$dst" "$dst.bak"
    fi
    ln -sfn "$src" "$dst"
    info "linked: $dst"
done

echo ""
bold "Done! Log out and back in (or reboot) for all changes to take effect."

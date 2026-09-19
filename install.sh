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
    local raw="${1%%.*}"
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

if [ -d /etc/nixos ]; then
    select_gpu "$(detect_gpu)"
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
DOTFILES_REPO=$DOTFILES
EOF
    info "saved vars to /etc/nixos/.dotfiles-vars"

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
bold "To receive future updates: ./update.sh"

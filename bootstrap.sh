#!/usr/bin/env bash
# bootstrap.sh — run this from the NixOS live ISO AFTER partitioning and
# mounting your drives at /mnt. It copies the config, generates hardware
# detection, and runs nixos-install so you can reboot straight into the
# finished system.
#
# One-liner from the ISO:
#   nix-shell -p git --run "git clone https://github.com/ExpressoCodes/NixPresso && cd NixPresso && bash bootstrap.sh"
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
MNT="${MNT:-/mnt}"

# ── Helpers ───────────────────────────────────────────────────────────────────
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
info()  { printf '  %s\n' "$*"; }
ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; }
die()   { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

ask() {
    local prompt="$1" default="$2" answer
    read -rp "$(bold "$prompt") [$default]: " answer
    echo "${answer:-$default}"
}

detect_gpu() {
    local pci has_intel=false has_amd=false has_nvidia=false
    pci=$(lspci 2>/dev/null || true)
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
    local raw="${1%%.*}" bus slot
    bus="${raw%%:*}"; slot="${raw##*:}"
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
    local map=( "" intel amd nvidia intel-nvidia amd-nvidia ) default_idx=1
    for i in 1 2 3 4 5; do [ "${map[$i]}" = "$detected" ] && default_idx=$i; done
    local choice
    read -rp "$(bold "Choice") [$default_idx]: " choice
    GPU_VARIANT="${map[${choice:-$default_idx}]:-intel}"
}

write_gpu_nix() {
    local variant="$1" dest="$MNT/etc/nixos/hardware-acceleration.nix"
    local src="$DOTFILES/nixos/gpu/$variant.nix"
    case "$variant" in
        intel-nvidia)
            local intel_raw nvidia_raw
            intel_raw=$(lspci | grep -i 'Intel.*VGA\|VGA.*Intel\|Intel.*Graphics' | awk '{print $1}' | head -1)
            nvidia_raw=$(lspci | grep -i 'NVIDIA.*VGA\|VGA.*NVIDIA' | awk '{print $1}' | head -1)
            sed -e "s/INTEL_BUS_ID/$(pci_to_nix "$intel_raw")/g" \
                -e "s/NVIDIA_BUS_ID/$(pci_to_nix "$nvidia_raw")/g" \
                "$src" > "$dest"
            info "Intel bus: $(pci_to_nix "$intel_raw")  NVIDIA bus: $(pci_to_nix "$nvidia_raw")"
            ;;
        amd-nvidia)
            local amd_raw nvidia_raw
            amd_raw=$(lspci | grep -i 'AMD.*VGA\|VGA.*AMD\|Radeon' | awk '{print $1}' | head -1)
            nvidia_raw=$(lspci | grep -i 'NVIDIA.*VGA\|VGA.*NVIDIA' | awk '{print $1}' | head -1)
            sed -e "s/AMD_BUS_ID/$(pci_to_nix "$amd_raw")/g" \
                -e "s/NVIDIA_BUS_ID/$(pci_to_nix "$nvidia_raw")/g" \
                "$src" > "$dest"
            info "AMD bus: $(pci_to_nix "$amd_raw")  NVIDIA bus: $(pci_to_nix "$nvidia_raw")"
            ;;
        *)
            cp "$src" "$dest"
            ;;
    esac
}

# ── Preflight ─────────────────────────────────────────────────────────────────
[ -d "$MNT/etc" ] || die "$MNT doesn't look like a mounted NixOS root. Mount your drives first, or set MNT=/your/mountpoint."
[ "$(id -u)" = "0" ] || die "Run as root (sudo bash bootstrap.sh)"

echo ""
bold "── NixOS Dotfiles Bootstrap ──────────────────────────────────────"
bold "   Mount point: $MNT"
echo ""

# ── Gather config ─────────────────────────────────────────────────────────────
HOSTNAME=$(ask "Hostname"  "nixos")
USERNAME=$(ask "Username"  "user")
select_gpu "$(detect_gpu)"
echo ""

# ── Generate hardware config ──────────────────────────────────────────────────
bold "→ Generating hardware-configuration.nix ..."
nixos-generate-config --root "$MNT"
ok "hardware-configuration.nix written"

# ── Copy dotfiles nixos/ config ───────────────────────────────────────────────
bold "→ Copying NixOS config to $MNT/etc/nixos/ ..."
for src in "$DOTFILES/nixos"/*; do
    [ -f "$src" ] || continue
    fname="$(basename "$src")"
    sed -e "s/yourhostname/$HOSTNAME/g" \
        -e "s/yourusername/$USERNAME/g" \
        "$src" > "$MNT/etc/nixos/$fname"
    info "wrote $fname"
done

bold "→ Writing hardware-acceleration.nix ($GPU_VARIANT) ..."
write_gpu_nix "$GPU_VARIANT"
ok "hardware-acceleration.nix written"

# Save vars so post-boot install.sh and update.sh work without re-asking
cat > "$MNT/etc/nixos/.dotfiles-vars" <<EOF
DOTFILES_HOSTNAME=$HOSTNAME
DOTFILES_USERNAME=$USERNAME
DOTFILES_GPU_VARIANT=$GPU_VARIANT
DOTFILES_REPO=/home/$USERNAME/NixPresso
EOF
chmod 644 "$MNT/etc/nixos/.dotfiles-vars"
ok "saved .dotfiles-vars"

# ── Install ───────────────────────────────────────────────────────────────────
bold "→ Running nixos-install ..."
nixos-install --root "$MNT" --flake "$MNT/etc/nixos#$HOSTNAME" --no-root-passwd

echo ""
bold "────────────────────────────────────────────────────────────────────"
bold "✓ Installation complete!"
echo ""
info "After rebooting, log in as $USERNAME and run:"
info ""
info "  git clone https://github.com/ExpressoCodes/NixPresso ~/NixPresso"
info "  cd ~/NixPresso && ./install.sh"
info ""
info "That symlinks ~/.config entries and applies the home config."
bold "────────────────────────────────────────────────────────────────────"

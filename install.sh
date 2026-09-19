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
echo ""

# ── NixOS system config ───────────────────────────────────────────────────────
if [ -d /etc/nixos ]; then
    bold "→ Copying NixOS config to /etc/nixos/ ..."
    for src in "$DOTFILES/nixos"/*; do
        fname="$(basename "$src")"
        # Substitute placeholders; write with sudo
        sudo sed \
            -e "s/yourhostname/$HOSTNAME/g" \
            -e "s/yourusername/$USERNAME/g" \
            "$src" | sudo tee "/etc/nixos/$fname" > /dev/null
        info "wrote /etc/nixos/$fname"
    done

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

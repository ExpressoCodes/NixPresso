#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$HOME/.config"

link() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        echo "  backing up existing: $dst -> $dst.bak"
        mv "$dst" "$dst.bak"
    fi
    ln -sfn "$src" "$dst"
    echo "  linked: $dst"
}

echo "Linking ~/.config entries..."
for dir in "$DOTFILES/home/.config"/*/; do
    name="$(basename "$dir")"
    link "$dir" "$CONFIG/$name"
done

echo ""
echo "Done. NixOS config lives in nixos/ — copy to /etc/nixos/ manually:"
echo "  sudo cp -r $DOTFILES/nixos/* /etc/nixos/"
echo "  # Edit nixos/configuration.nix (username, hostname, timezone)"
echo "  # Run: sudo nixos-generate-config  (for hardware-configuration.nix)"
echo "  sudo nixos-rebuild switch --flake /etc/nixos#yourhostname"

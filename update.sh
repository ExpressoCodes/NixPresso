#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
VARS_FILE="/etc/nixos/.dotfiles-vars"

# ── Helpers ───────────────────────────────────────────────────────────────────
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
info()  { printf '  %s\n' "$*"; }
ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; }
skip()  { printf '  \033[33m–\033[0m %s\n' "$*"; }

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
bold "→ Pulling latest changes ..."
git -C "$DOTFILES" pull --ff-only
echo ""

# ── ~/.config + ~/.local/share (symlinked — already updated by git pull) ──────
bold "→ Home config (~/.config, ~/.local/share): updated via symlinks."
echo ""

# ── NixOS config ──────────────────────────────────────────────────────────────
if [ ! -d /etc/nixos ]; then
    info "/etc/nixos not found — skipping NixOS update."
    exit 0
fi

if [ ! -f "$VARS_FILE" ]; then
    bold "No $VARS_FILE found."
    info "Run ./install.sh first to set up NixOS config, then use ./update.sh for future updates."
    exit 1
fi

# Load saved values from install
# shellcheck source=/dev/null
source "$VARS_FILE"
HOSTNAME="$DOTFILES_HOSTNAME"
USERNAME="$DOTFILES_USERNAME"
GPU_VARIANT="$DOTFILES_GPU_VARIANT"

bold "→ Applying NixOS updates (hostname=$HOSTNAME, user=$USERNAME, gpu=$GPU_VARIANT) ..."
bold "→ Requesting sudo ..."
sudo -v
( while true; do sudo -n true; sleep 50; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

UPDATED=0

BASE_PKGS="/etc/nixos/.dotfiles-packages-base.json"

for src in "$DOTFILES/nixos"/*; do
    [ -f "$src" ] || continue
    fname="$(basename "$src")"
    dest="/etc/nixos/$fname"

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

    # File differs — show diff and ask
    echo ""
    bold "  $fname has local differences:"
    diff <(echo "$current") <(echo "$new") | sed 's/^/    /' || true
    echo ""
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
    read -rp "  $(bold "[U]pdate / [S]kip") [u]: " ans
    ans="${ans:-u}"
    if [[ "$ans" =~ ^[Uu] ]]; then
        echo "$new" | sudo tee "$dest" > /dev/null
        ok "updated: hardware-acceleration.nix"
        UPDATED=1
    else
        skip "kept local: hardware-acceleration.nix"
    fi
else
    echo "$new" | sudo tee "$dest" > /dev/null
    ok "new: hardware-acceleration.nix"
    UPDATED=1
fi

echo ""
if [ "$UPDATED" -eq 1 ]; then
    bold "→ Running nixos-rebuild switch ..."
    sudo nixos-rebuild switch --flake "/etc/nixos#$HOSTNAME"
else
    bold "→ No NixOS changes — skipping rebuild."
fi

echo ""
bold "Done!"

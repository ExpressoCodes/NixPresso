# NixPresso

NixOS + Hyprland desktop. Clone and run one script to get the full setup on any existing NixOS system.

## Stack

| Layer | Tool |
|---|---|
| OS | NixOS (flake, unstable) |
| WM | Hyprland |
| Top bar | Quickshell (QML) |
| Dock | qs-dock |
| Terminal | Kitty (Gruvbox Dark) |
| Launcher | Rofi |
| Notifications | Mako |
| Wallpaper | Hyprpaper |
| Package manager TUI | NixStore |

---

## Install

Requires a running NixOS system (any base install).

```bash
git clone https://github.com/ExpressoCodes/NixPresso ~/NixPresso
cd ~/NixPresso && ./install.sh
```

`install.sh` will:
- Ask for **hostname**, **username**
- Auto-detect your GPU and ask to confirm (Intel / AMD / NVIDIA / hybrid)
- Request sudo once, keep it alive for the rebuild
- Copy and substitute the NixOS config into `/etc/nixos/`
- Run `nixos-rebuild switch`
- Symlink all `~/.config` entries (Hyprland, Quickshell, qs-dock, Kitty, Rofi, Mako)

Reboot and you're in.

---

## Repo layout

```
install.sh            # full setup on an existing NixOS system
update.sh             # pull upstream changes safely

nixos/                # → /etc/nixos/  (system config)
  flake.nix
  configuration.nix   # hostname / username / locale — substituted by install.sh
  hyprland.nix        # Hyprland, greetd, hyprlock, polkit, portals
  hardware-acceleration.nix   # written from nixos/gpu/ by install.sh
  gpu/                # one variant per GPU type
    intel.nix
    amd.nix
    nvidia.nix
    intel-nvidia.nix  # PRIME offload, bus IDs auto-detected
    amd-nvidia.nix
  fonts.nix
  boot.nix
  nixstore.nix
  dotfiles-updater.nix
  packages.json       # managed by NixStore; 3-way merged on update

home/.config/         # → ~/.config/  (symlinked by install.sh)
  hypr/               # Hyprland keybinds, monitors, autostart
  quickshell/         # top bar QML (workspaces · clock · tray)
  qs-dock/            # dock settings
  kitty/              # terminal + Gruvbox Dark theme
  mako/               # notification style
  rofi/               # launcher config

home/.local/share/    # → ~/.local/share/  (symlinked by install.sh)
  rofi/themes/        # rounded-nord-dark + rounded-common themes
```

---

## GPU support

Auto-detected from `lspci` at install time. Override at the menu:

| Option | Config used |
|---|---|
| `intel` | Intel VA-API + iHD driver |
| `amd` | AMDVLK + ROCm |
| `nvidia` | Proprietary, modesetting |
| `intel-nvidia` | Intel iGPU daily + NVIDIA PRIME offload (`nvidia-offload <cmd>`) |
| `amd-nvidia` | AMD iGPU daily + NVIDIA PRIME offload |

---

## Customisation

- **Packages** — open NixStore (`nixstore` in launcher) to add/remove
- **Monitors** — edit `~/.config/hypr/hyprland.lua` (`hl.monitor` blocks)
- **Wallpaper** — drop an image in `~/Pictures/wallpapers/` and update `~/.config/hypr/hyprpaper.conf`
- **Bar / dock** — edit `~/.config/quickshell/` QML files or `~/.config/qs-dock/settings.json`
- **Locale / timezone** — edit `nixos/configuration.nix` (look for `# TODO`)

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

## Requirements

- **NixOS** already installed (any base install — graphical or minimal)
- **Git** available in the current shell (`nix-shell -p git` works on a fresh install)
- **jq** — used by `update.sh` for package merging (`nix-shell -p jq`)
- **pciutils** (`lspci`) — used at install/update time to detect GPU bus IDs
- **sudo** access for the installing user
- Enough disk space for a NixOS rebuild (~2 GB for the initial closure)

`dconf` is optional — only needed if you want GNOME/GTK settings applied.

---

## Install

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

## Update

```bash
cd ~/NixPresso && ./update.sh
```

`update.sh` will:
- Pull the latest upstream changes (`git pull --ff-only`)
- Home config (`~/.config`, `~/.local/share`) is already live — updated automatically via symlinks
- Re-apply dconf settings from `home/apply-dconf.sh` if present
- For each NixOS config file in `nixos/`:
  - **`packages.json`** — 3-way merge: upstream additions/removals are shown, your own packages are always preserved; you're prompted before any upstream package change is applied
  - **All other files** — substitutes your hostname/username, shows a diff if anything changed, and asks `[U]pdate / [S]kip` before overwriting
- Re-generates `hardware-acceleration.nix` from your saved GPU variant + live PCI bus IDs
- Runs `nixos-rebuild switch` only when at least one file was actually changed; skips the rebuild entirely if nothing changed

Your saved settings (hostname, username, GPU variant) are read from `/etc/nixos/.dotfiles-vars` written by `install.sh` — run `install.sh` first if that file is missing.

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

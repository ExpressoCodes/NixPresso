# NixPresso

NixOS + Hyprland desktop. Clone and run one script to rebuild the full system on a new machine.

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

## Fresh install (new machine)

### 1. Boot the NixOS ISO and partition your drives

Follow the [NixOS manual](https://nixos.org/manual/nixos/stable/#sec-installation-manual) for partitioning and mounting. Mount your root at `/mnt`.

### 2. Clone and bootstrap

```bash
nix-shell -p git --run \
  "git clone https://github.com/ExpressoCodes/NixPresso && cd NixPresso && sudo bash bootstrap.sh"
```

`bootstrap.sh` will:
- Ask for **hostname** and **username**
- Auto-detect your GPU and ask to confirm (Intel / AMD / NVIDIA / hybrid)
- Run `nixos-generate-config` for your hardware
- Copy and substitute the NixOS config into `/mnt/etc/nixos/`
- Run `nixos-install --flake /mnt/etc/nixos#<hostname>`

### 3. Reboot, then finish the home config

```bash
git clone https://github.com/ExpressoCodes/NixPresso ~/NixPresso
cd ~/NixPresso && ./install.sh
```

`install.sh` symlinks `~/.config/*` entries (Hyprland, Quickshell, qs-dock, Kitty, Rofi, Mako) and runs `nixos-rebuild switch` to apply any pending system config.

---

## Migrating an existing NixOS system

```bash
git clone https://github.com/ExpressoCodes/NixPresso ~/NixPresso
cd ~/NixPresso && ./install.sh
```

That's it. `install.sh` handles GPU detection, username/hostname substitution, `nixos-rebuild`, and home config symlinks in one go.

---

## Keeping up to date

```bash
cd ~/NixPresso && ./update.sh
```

Or press **Ctrl+U** inside NixStore.

`update.sh`:
- `git pull`
- Re-applies NixOS config files; shows a diff and asks before touching anything you've locally modified
- 3-way merges `packages.json` so your added/removed packages are always respected
- Skips `nixos-rebuild` if nothing changed

A systemd user timer also fires every 6 hours and sends a mako notification when upstream commits are available.

---

## Repo layout

```
bootstrap.sh          # fresh NixOS ISO install
install.sh            # post-boot or existing-system setup
update.sh             # pull upstream changes safely

nixos/                # → /etc/nixos/  (system config)
  flake.nix
  configuration.nix   # hostname / username / locale — set by install scripts
  hyprland.nix        # Hyprland, greetd, hyprlock, polkit, portals
  hardware-acceleration.nix   # written from nixos/gpu/ by install scripts
  gpu/                # one variant per GPU type
    intel.nix
    amd.nix
    nvidia.nix
    intel-nvidia.nix  # PRIME offload, bus IDs auto-detected
    amd-nvidia.nix
  fonts.nix
  boot.nix
  nixstore.nix        # NixStore TUI package manager
  dotfiles-updater.nix  # systemd timer for update notifications
  packages.json       # managed by NixStore; 3-way merged on update

home/.config/         # → ~/.config/  (user config, symlinked)
  hypr/               # Hyprland keybinds, monitors, autostart
  quickshell/         # top bar QML (workspaces · clock · tray)
  qs-dock/            # dock settings
  kitty/              # terminal + Gruvbox Dark theme
  mako/               # notification style
  rofi/               # launcher
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

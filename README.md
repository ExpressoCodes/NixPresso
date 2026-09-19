# dotfiles

NixOS + Hyprland setup with a custom Quickshell top bar and qs-dock.

## Stack

| Layer | Tool |
|---|---|
| OS | NixOS (flake-based) |
| WM | Hyprland |
| Top bar | Quickshell (QML) |
| Dock | qs-dock |
| Terminal | Kitty |
| Launcher | Rofi |
| Notifications | Mako |
| Wallpaper | Hyprpaper |

## Layout

```
nixos/          → /etc/nixos/      (system config, managed as root)
home/.config/   → ~/.config/       (user config, symlinked by install.sh)
```

## Install

### 1. NixOS system config

```bash
sudo cp -r nixos/* /etc/nixos/
sudo nixos-generate-config   # generates hardware-configuration.nix
```

Edit `nixos/configuration.nix` — look for `# TODO` comments:
- `networking.hostName` — your machine name
- `users.users."yourusername"` — your username
- `time.timeZone` / `i18n` — your locale

Then rebuild:
```bash
sudo nixos-rebuild switch --flake /etc/nixos#yourhostname
```

### 2. User config (home/.config)

```bash
chmod +x install.sh
./install.sh
```

This symlinks each `home/.config/<name>` directory into `~/.config/`.
Existing directories are backed up with a `.bak` suffix.

### 3. Rofi theme

The rofi config references `~/.local/share/rofi/themes/rounded-nord-dark.rasi`.
Install it with:
```bash
mkdir -p ~/.local/share/rofi/themes
# download from: https://github.com/newmanls/rofi-themes-collection
```

### 4. Kitty theme

The kitty config includes `current-theme.conf` (Gruvbox Dark).
To apply it interactively: `kitten themes`

## Wallpaper

`hyprpaper.conf` points to `~/Pictures/wallpapers/qingbao.jpg`.
Replace with your own image or update the path in `home/.config/hypr/hyprpaper.conf`.

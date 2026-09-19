{ inputs, config, pkgs, ... }:

let
  hyprPkgs = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};

  # Single session entry for tuigreet, so its status bar shows "Hyprland"
  # instead of the full start-hyprland store path.
  greeterSessions = pkgs.writeTextDir "share/wayland-sessions/hyprland.desktop" ''
    [Desktop Entry]
    Name=Hyprland
    Exec=${config.programs.hyprland.package}/bin/start-hyprland
    Type=Application
  '';
in
{

  nix.settings = {
    substituters = ["https://hyprland.cachix.org"];
    trusted-public-keys = ["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="];
  };

  programs.hyprland = {
    enable = true;
    package = hyprPkgs.hyprland;
    # Portal must come from the same flake as Hyprland, or screensharing breaks.
    portalPackage = hyprPkgs.xdg-desktop-portal-hyprland;
  };

  # Login greeter. start-hyprland is the recommended launcher (watchdog/crash recovery).
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --asterisks --sessions ${greeterSessions}/share/wayland-sessions";
        user = "greeter";
      };
    };
  };

  # Authentication agent (password prompts for pkexec, disk mounts, etc.).
  security.polkit.enable = true;
  systemd.packages = [ pkgs.hyprpolkitagent ];
  systemd.user.services.hyprpolkitagent.wantedBy = [ "graphical-session.target" ];

  # Screen locker, with the PAM entry it needs to accept your password.
  programs.hyprlock.enable = true;

  # Portal for file pickers etc. (XDPH does not implement those).
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  # Run Electron/Chromium apps (Brave, VS Code, ...) natively on Wayland.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  environment.systemPackages = [
    inputs.hyprland-settings.packages.x86_64-linux.default
  ];

}

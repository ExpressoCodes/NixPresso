{ config, lib, pkgs, ... }:
let
  useEfi = YOUREFIMODE;          # installer substitutes: true or false
  grubDevice = "YOURGRUBDEVICE"; # installer substitutes: e.g. /dev/vda (only used when !useEfi)
in {
  boot = {
    kernelPackages = pkgs.linuxPackages_latest;

    loader = lib.mkMerge [
      (lib.mkIf useEfi {
        systemd-boot.enable = true;
        systemd-boot.editor = false;
        efi.canTouchEfiVariables = true;
      })
      (lib.mkIf (!useEfi) {
        grub = {
          enable = true;
          device = grubDevice;
          useOSProber = false;
        };
      })
    ];

    kernelParams = [
      "quiet"
      "splash"
      "vga=current"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];
    consoleLogLevel = 0;

    initrd = {
      systemd.enable = true;
      verbose = false;
    };
  };
}

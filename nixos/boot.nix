{ config, lib, pkgs, ... }:

{
    boot = {
    # Stay up-to-date on the kernel.
      kernelPackages = pkgs.linuxPackages_latest;
      loader = {
        systemd-boot.editor = false;
        # Use the systemd-boot EFI boot loader.
        systemd-boot.enable = true;
        efi.canTouchEfiVariables = true;
      };

      # Silent Boot
      kernelParams = [
        "quiet"
        "splash"
        "vga=current"
        "rd.systemd.show_status=false"
        "rd.udev.log_level=3"
        "udev.log_priority=3"
      ];
      consoleLogLevel = 0;
    };

    # LUKS prompt
    boot = {
      initrd = {
        systemd.enable = true;
        verbose = false;
      };
    };
}

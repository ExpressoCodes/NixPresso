{ config, pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ mesa ];
    extraPackages32 = with pkgs; [ pkgs.pkgsi686Linux.mesa ];
  };

  boot.initrd.kernelModules = [ "vmwgfx" ];

  virtualisation.vmware.guest.enable = true;

  environment.systemPackages = with pkgs; [ swaybg ];

  environment.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS = "1";
    LIBGL_ALWAYS_SOFTWARE = "1";
    WLR_RENDERER = "pixman";
  };
}

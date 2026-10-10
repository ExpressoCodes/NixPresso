{ config, pkgs, ... }:

{
  # QEMU / KVM / VirtualBox — virtio-gpu with hardware-accelerated GL (virgl).
  # For VMware Fusion, use vmware.nix instead.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ mesa ];
    extraPackages32 = with pkgs; [ pkgs.pkgsi686Linux.mesa ];
  };

  # Load the virtio GPU driver early so the display is available at the greeter
  boot.initrd.kernelModules = [ "virtio_gpu" ];

  # QEMU guest agent: graceful shutdown, snapshot freeze/thaw, clock sync
  services.qemuGuest.enable = true;

  # SPICE vdagent: clipboard sync + dynamic resolution resize from the host
  services.spice-vdagentd.enable = true;
}

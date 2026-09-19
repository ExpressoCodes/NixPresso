{ config, pkgs, ... }:

# Intel iGPU + NVIDIA dGPU (PRIME offload).
# Bus IDs are substituted by install.sh — adjust if auto-detection was wrong.
{
  nixpkgs.config.packageOverrides = pkgs: {
    vaapiIntel = pkgs.vaapiIntel.override { enableHybridCodec = true; };
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      vpl-gpu-rt
    ];
  };

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;  # adds `nvidia-offload` wrapper command
      };
      intelBusId  = "INTEL_BUS_ID";   # substituted by install.sh
      nvidiaBusId = "NVIDIA_BUS_ID";  # substituted by install.sh
    };
  };

  services.xserver.videoDrivers = [ "nvidia" ];
}

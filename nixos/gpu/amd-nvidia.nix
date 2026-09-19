{ config, pkgs, ... }:

# AMD iGPU + NVIDIA dGPU (PRIME offload).
# Bus IDs are substituted by install.sh — adjust if auto-detection was wrong.
{
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      amdvlk
      rocmPackages.clr.icd
    ];
    extraPackages32 = with pkgs; [
      driversi686Linux.amdvlk
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
        enableOffloadCmd = true;
      };
      amdgpuBusId  = "AMD_BUS_ID";    # substituted by install.sh
      nvidiaBusId  = "NVIDIA_BUS_ID"; # substituted by install.sh
    };
  };

  services.xserver.videoDrivers = [ "nvidia" ];
}

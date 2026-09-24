{ config, pkgs, ... }:

{
  nixpkgs.config.packageOverrides = pkgs: {
    vaapiIntel = pkgs.vaapiIntel.override { enableHybridCodec = true; };
  };
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-vaapi-driver  # i965 — correct for Gen8 (Broadwell) and older; iHD (intel-media-driver) is Gen9+ only
      libvdpau-va-gl
      mesa
    ];
  };

  # libglvnd needs this to locate Mesa's EGL vendor on nixpkgs-unstable,
  # where hardware.graphics does not set __EGL_VENDOR_LIBRARY_DIRS.
  environment.sessionVariables = {
    __EGL_VENDOR_LIBRARY_DIRS = "/run/opengl-driver/share/glvnd/egl_vendor.d";
  };
}

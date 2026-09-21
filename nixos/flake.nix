{
  description = "NixOS + Hyprland dotfiles";

  # ── Inputs ────────────────────────────────────────────────────────────────
  # To add a source: append a new block here and reference it in outputs below.
  # To remove a source: delete its block here and its entry in outputs below.
  #
  # nixstore-managed inputs live in nixstore-inputs.nix and are merged in below.

  inputs = {

    # nixpkgs ─────────────────────────────────────────────────────────────────
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # hyprland ────────────────────────────────────────────────────────────────
    hyprland.url = "github:hyprwm/Hyprland";

    # nixstore ────────────────────────────────────────────────────────────────
    nixstore = {
      url = "github:ExpressoCodes/nixstore";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  } // (import ./nixstore-inputs.nix);

  # ── Outputs ───────────────────────────────────────────────────────────────

  outputs =
    {
      nixpkgs,           # nixpkgs
      hyprland,          # hyprland
      hyprland-settings, # hyprland-settings (via nixstore-inputs.nix)
      uxplay,            # uxplay            (via nixstore-inputs.nix)
      ...                # nixstore (accessed via inputs.nixstore in configuration.nix)
    } @ inputs:
    {
      nixosConfigurations.yourhostname = nixpkgs.lib.nixosSystem { # TODO: match networking.hostName in configuration.nix
        specialArgs = { inherit inputs; };
        system = "x86_64-linux";
        modules = [
          (import ./configuration.nix)
        ];
      };
    };
}

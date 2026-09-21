{
  description = "NixOS + Hyprland dotfiles";

  # ── Inputs ────────────────────────────────────────────────────────────────
  # To add a source: append a new block here and reference it in outputs below.
  # To remove a source: delete its block here and its entry in outputs below.
  #
  # nixstore manages inputs directly in this block (string-patching this file).

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

    # uxplay ──────────────────────────────────────────────────────────────────
    uxplay.url = "github:ExpressoCodes/uxplay";

    # hyprland-settings ───────────────────────────────────────────────────────
    hyprland-settings.url = "github:ExpressoCodes/hyprland-settings";

  };

  # ── Outputs ───────────────────────────────────────────────────────────────

  outputs =
    {
      nixpkgs,           # nixpkgs
      hyprland,          # hyprland
      hyprland-settings, # hyprland-settings
      uxplay,            # uxplay
      ...                # nixstore (accessed via inputs.nixstore in configuration.nix)
    } @ inputs:
    let
      # Read modules.json to get enabled flake modules.
      # Use builtins.pathExists so it degrades gracefully if the file doesn't exist yet.
      modulesFile = ./modules.json;
      modulesData = if builtins.pathExists modulesFile
        then builtins.fromJSON (builtins.readFile modulesFile)
        else {};

      lib = nixpkgs.lib;

      # Filter to only enabled flake-module entries.
      enabledFlakeModules = builtins.filter
        (entry: entry.type == "flake-module" && entry.enabled == true)
        (builtins.attrValues modulesData);

      # Build the import list — only include entries whose input exists in `inputs`.
      flakeModuleImports = builtins.map
        (entry: inputs.${entry.input}.nixosModules.default)
        (builtins.filter
          (entry: inputs ? ${entry.input}
                && inputs.${entry.input} ? nixosModules
                && inputs.${entry.input}.nixosModules ? default)
          enabledFlakeModules);

      # Build a plain NixOS module for program-option entries (e.g. programs.localsend.enable).
      # Doing this here (plain Nix) avoids referencing `config` inside the module system,
      # which would cause infinite recursion.
      programOptionEntries = builtins.filter
        (entry: (entry.type or "") == "program-option" && entry.enabled or false)
        (builtins.attrValues modulesData);

      programOptionModule = builtins.foldl'
        (acc: entry:
          let
            optPath = lib.splitString "." entry.option;
            parentPath = lib.init optPath;
            baseAttrs = lib.setAttrByPath optPath true;
            extrasAttrs = lib.optionalAttrs (entry ? extras) (lib.setAttrByPath parentPath entry.extras);
          in
          lib.recursiveUpdate acc (lib.recursiveUpdate baseAttrs extrasAttrs))
        {}
        programOptionEntries;
    in
    {
      nixosConfigurations.yourhostname = nixpkgs.lib.nixosSystem { # TODO: match networking.hostName in configuration.nix
        specialArgs = { inherit inputs; };
        system = "x86_64-linux";
        modules = [
          (import ./configuration.nix)
          programOptionModule
        ] ++ flakeModuleImports;
      };
    };
}

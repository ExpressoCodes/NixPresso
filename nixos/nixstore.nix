{ inputs, pkgs, ... }:
{
  imports = [ inputs.nixstore.nixosModules.default ];

  # NixStore: TUI to search/install/remove packages; manages ./packages.json.
  programs.nixstore = {
    enable = true;
    packagesFile = ./packages.json;
    modulesFile = ./modules.json;
    inputsFile = ./nixstore-inputs.nix;
    terminalCommand = "${pkgs.kitty}/bin/kitty --class nixstore --title NixStore";
  };
}

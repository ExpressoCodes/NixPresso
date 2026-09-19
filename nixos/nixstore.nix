{ inputs, pkgs, ... }:
{
  imports = [ inputs.nixstore.nixosModules.default ];

  # NixStore: TUI to search/install/remove packages; manages ./packages.json.
  programs.nixstore = {
    enable = true;
    packagesFile = ./packages.json;
    terminalCommand = "${pkgs.kitty}/bin/kitty --class nixstore --title NixStore";
  };
}

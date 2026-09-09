# User-level Home Manager configuration for nabu.
#
# Split by concern: fonts/theme are presentation, apps are daily software,
# terminal holds the kitty setup, dev is development tooling, flatpak is app
# distribution.  Imported as home-manager.users.nabu from nixos/configuration.nix.
{
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
    ./fonts.nix
    ./theme.nix
    ./apps.nix
    ./terminal.nix
    ./dev.nix
    ./flatpak.nix
  ];

  home.stateVersion = "26.11";
}

# Base NixOS configuration for Xiaomi Pad 5 (nabu).
# The current image imports niri + Noctalia; standalone variants are planned.
#
# This file is the assembly entry point only:
#   - modules/system/  system-level config (base, users, packages, network,
#                      boot, nabu hardware, niri+Noctalia desktop)
#   - modules/home/    user-level Home Manager config (fonts, theme, apps, ...)
#   - modules/build/   image/artifact builders consumed by flake.nix
{
  inputs,
  pkgs,
  ...
}:

{
  imports = [
    ./modules/system
    ./modules/build
  ];

  # == Home Manager (per-user config; see nixos/modules/home/) ================
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.nabu = import ./modules/home;
  home-manager.extraSpecialArgs = { inherit inputs; };

  # Produce an uncompressed raw ext4 .img — directly flashable via
  # `fastboot flash linux nabu-rootfs.ext4.img`
  nabu.image.compress = false;
}

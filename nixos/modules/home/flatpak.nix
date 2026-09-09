# Flatpak applications (system service enabled in ../system/packages.nix).
{ ... }:

{
  services.flatpak.enable = true;
  services.flatpak.packages = [
    "cn.wps.wps_365"
  ];
}

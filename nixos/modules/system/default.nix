# System-level module set: device bring-up and system services.
#
# Daily-use configuration lives here.  Image/artifact builders are under
# ../build, per-user Home Manager config under ../home.
{
  imports = [
    ./base.nix
    ./users.nix
    ./packages.nix
    ./network.nix
    ./boot.nix
    ./hardware-nabu.nix
    ./desktop.nix
  ];
}

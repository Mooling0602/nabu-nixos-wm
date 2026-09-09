# Image and artifact builders for flashing nabu.
#
# These modules only define system.build.* outputs (and the nabu.image
# options); they are consumed by flake.nix packages and scripts, and are not
# needed on the running device.
{
  imports = [
    ./esp-image.nix
    ./rootfs-image.nix
  ];
}

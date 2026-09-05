# Unified Kernel Image for nabu, built with nixpkgs' native boot.uki support.
#
# The Project Aloha UEFI firmware cannot reliably hand the device tree to an
# EFI-stub kernel, so the DTB must be embedded in the UKI itself (the same
# conclusion the reference Fedora image reached: its kernel spec builds the UKI
# with `ukify --devicetree=...`).  nixpkgs' boot.uki module already knows how
# to do this: it wires Linux/Initrd/Stub to the right places and picks up
# DeviceTree from hardware.deviceTree.
{
  config,
  lib,
  ...
}:

{
  # Build and expose the nabu device tree so the UKI builder can embed it.
  hardware.deviceTree = {
    enable = true;
    # Path relative to ${kernel}/dtbs.  arm64 `make dtbs_install` keeps the
    # vendor subdirectory, so the full path is
    # ${kernel}/dtbs/qcom/sm8150-xiaomi-nabu.dtb.
    name = "qcom/sm8150-xiaomi-nabu.dtb";
  };

  # Give the UKI a stable name.  With the default `boot.uki.version = null`
  # (system.image.version), the resulting file is simply `nabu.efi`, matching
  # the stable rEFInd menu entry in hardware-nabu.nix.
  boot.uki.name = "nabu";

  # Use a stable init= path instead of the default per-generation
  # `${toplevel}/init`, for two reasons:
  #
  #   1. The UKI is deployed by boot.loader.external.installHook, which
  #      system.build.toplevel references.  If the UKI's cmdline referenced the
  #      toplevel, evaluation would recurse forever
  #      (toplevel -> installHook -> uki -> toplevel).
  #
  #   2. A stable init= means a single UKI serves every generation: rolling
  #      back only re-points the `system` profile at an older generation, which
  #      needs no UKI rebuild and never fills the ESP.  The UKI itself is only
  #      rebuilt when the kernel or initrd actually change.
  boot.uki.settings.UKI.Cmdline = lib.mkForce (
    "init=/nix/var/nix/profiles/system/init ${toString config.boot.kernelParams}"
  );
}

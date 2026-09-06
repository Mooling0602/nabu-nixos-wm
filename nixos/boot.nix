# Boot via systemd-boot: no UKI, no rEFInd.
#
# The Project Aloha UEFI firmware boots the removable-media fallback path
# /EFI/BOOT/BOOTAA64.EFI and has no usable NVRAM boot variables, so we set
# boot.loader.efi.canTouchEfiVariables = false: bootctl then installs
# systemd-boot to that fallback path (plus /EFI/systemd/).
#
# The device tree is installed to the ESP and handed to the EFI-stub kernel by
# systemd-boot through the Boot Loader Spec `devicetree` keyword — nixpkgs
# wires this up natively via boot.loader.systemd-boot.installDeviceTree, so no
# `dtb=` kernel parameter and no UKI are needed.
{
  ...
}:

{
  # Build the nabu device tree so systemd-boot can install it to the ESP.
  hardware.deviceTree = {
    enable = true;
    # Path relative to ${kernel}/dtbs.  arm64 `make dtbs_install` keeps the
    # vendor subdirectory, so the full path is
    # ${kernel}/dtbs/qcom/sm8150-xiaomi-nabu.dtb.
    name = "qcom/sm8150-xiaomi-nabu.dtb";
  };

  boot.loader.systemd-boot = {
    enable = true;
    # Defaults to `hardware.deviceTree.enable && name != null`; kept explicit.
    installDeviceTree = true;

    # Android dualboot entry (Project Aloha's Reboot2Android stub).
    extraEntries."android.conf" = ''
      title Android
      efi /EFI/Android/Reboot2Android.efi
      sort-key o_android
    '';
  };

  boot.loader.efi = {
    # NixOS mounts the ESP at /boot/efi (see hardware-nabu.nix).
    efiSysMountPoint = "/boot/efi";
    # Project Aloha has no usable NVRAM boot variables; rely on the removable
    # fallback /EFI/BOOT/BOOTAA64.EFI instead.
    canTouchEfiVariables = false;
  };

  # Short boot-menu timeout before the default (NixOS) entry boots.
  boot.loader.timeout = 5;
}

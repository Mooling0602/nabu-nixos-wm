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

  # == Boot diagnostics =======================================================
  # Use this option instead of a second loglevel= argument: NixOS otherwise
  # appends its default loglevel=4 after manually supplied kernel parameters.
  boot.consoleLogLevel = 8;
  boot.plymouth.enable = false;
  boot.initrd.verbose = true;

  boot.kernelParams = [
    # EFI stub output uses the firmware console before Linux takes over.
    "efi=debug"
    # Record initcall progress and retain early messages until fbcon is ready.
    "ignore_loglevel"
    "printk.time=1"
    "log_buf_len=4M"
    "initcall_debug"
    # Bind immediately once MSM DRM provides a framebuffer; keep text visible.
    "fbcon=nodefer"
    "consoleblank=0"
    # These apply to both initrd and the main system, including early PID 1.
    # kmsg reaches the console and can be collected by journald once it starts.
    "systemd.show_status=yes"
    "systemd.log_level=debug"
    "systemd.log_target=kmsg"
  ];

  # Show initrd service output as well as manager status, retaining journal copies.
  boot.initrd.systemd.settings.Manager = {
    DefaultStandardOutput = "journal+console";
    DefaultStandardError = "journal+console";
  };

  # Preserve logs from previous boots, with bounded disk and runtime use.
  services.journald = {
    storage = "persistent";
    extraConfig = ''
      SystemMaxUse=256M
      RuntimeMaxUse=64M
      SyncIntervalSec=30s
    '';
  };
}

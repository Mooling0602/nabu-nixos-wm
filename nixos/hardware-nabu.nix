# Xiaomi Pad 5 (nabu) hardware configuration.
#
# Reference: jhuang6451/nabu_fedora (nabu-fedora-configs-core), sm8150-mainline.
#
# Boot chain on the device: UEFI (Project Aloha / DBKP) -> rEFInd -> UKI in ESP.
# The kernel command line is baked into the UKI; rootfs is identified by
# PARTLABEL=linux (ext4), ESP by PARTLABEL=esp.
{
  config,
  pkgs,
  ...
}:

{
  # == Platform ==============================================================
  nixpkgs.hostPlatform = "aarch64-linux";
  nixpkgs.flake.setNixPath = false;
  nixpkgs.flake.setFlakeRegistry = false;

  # == Kernel =================================================================
  boot.kernelPackages = pkgs.linuxKernel.packagesFor pkgs.kernel-sm8150;
  # No `quiet`: let kernel/systemd messages scroll on the console.
  boot.kernelParams = [
    "root=PARTLABEL=linux"
    "rw"
    "systemd.gpt_auto=no"
    "cryptomgr.notests"
    # Explicit text console: the nabu DTB has no simple-framebuffer node, so
    # the kernel must attach fbcon to tty0 to render early boot logs on the
    # panel (otherwise fbcon may not bind and the screen stays black).
    "console=tty0"
    "fbcon=rotate:1"
    "systemd.show_status=yes"
    "loglevel=7"
  ];

  # Boot splash: the nabu DTB has no simple-framebuffer node, so the panel
  # only comes up via the MSM DRM stack. The reference (nabu_fedora) ships
  # plymouth in the initrd (hostonly=no) to light the panel early. We keep
  # console=tty0 + loglevel=7 above so a failure still leaves text on screen.
  boot.plymouth.enable = true;

  # The ESP is owned by the rEFInd dualboot layout (rEFInd + Android entry);
  # NixOS only installs its UKI into it.  nixos-rebuild boot|switch runs this
  # hook, which deploys the freshly built UKI under the stable rEFInd menu
  # entry /EFI/nixos/nabu.efi, keeping the previous UKI as a fallback.
  boot.loader.external = {
    enable = true;
    installHook = pkgs.writeShellScript "nabu-install-uki" ''
      set -euo pipefail

      coreutils="${pkgs.coreutils}"
      uki="${config.system.build.uki}/${config.system.boot.loader.ukiFile}"
      dst_dir="/boot/efi/EFI/nixos"
      dst="$dst_dir/nabu.efi"

      # Keep the currently installed UKI as a "previous kernel" fallback.  If a
      # newly installed kernel fails to boot, rEFInd's auto-scan lists
      # nabu-previous.efi, so the older, working kernel can still be chosen
      # from the boot menu.  cmp skips the backup when nothing changed.
      if [ -e "$dst" ] && ! "$coreutils/bin/cmp" -s "$uki" "$dst"; then
        "$coreutils/bin/install" -m644 "$dst" "$dst_dir/nabu-previous.efi"
      fi

      # Install the new UKI under the stable rEFInd menu entry.
      "$coreutils/bin/install" -Dm644 "$uki" "$dst"

      echo "nabu: installed $uki -> $dst (previous kept as nabu-previous.efi)"
    '';
  };

  # Generic initramfs (not hostonly) with forced UFS drivers — the image is
  # built off-device and the rootfs lives on the UFS `linux` partition.
  # Mirrors the reference dracut config: hostonly=no + force_drivers ufs_qcom.
  # NixOS' default set is PC-oriented (AHCI/PATA/NVMe and assorted USB HID).
  # The Fedora-aligned nabu kernel intentionally does not provide several of
  # those drivers, and the root device is UFS.  Keep this initrd generic for
  # nabu hardware through the explicit list below, not generic for PCs.
  boot.initrd.includeDefaultModules = false;
  # Qualcomm's secure environment is not exposed as a PC-style TPM.  The
  # systemd package enables TPM units by default and would otherwise inject
  # tpm-tis/tpm-crb into the initrd, neither of which exists in this kernel.
  boot.initrd.systemd.tpm2.enable = false;
  systemd.tpm2.enable = false;
  boot.initrd.availableKernelModules = [
    "ufs_qcom"
    "ufshcd_pltfrm"
    "ufshcd_core"
    # Early display stack: no simple-framebuffer node, the panel is driven by
    # the MSM/KMS DRM driver, so it must be present in the initramfs for
    # plymouth/fbcon to light the screen before the rootfs is mounted.
    "drm"
    "drm_kms_helper"
    "msm"
    "panel_novatek_nt36523"
    "ktz8866"
  ];
  boot.initrd.kernelModules = [
    "ufs_qcom"
    "ufshcd_pltfrm"
  ];
  # MSM DRM is built into the kernel, so module-closure based firmware
  # discovery cannot see its runtime requests. Include the Adreno 640 blobs
  # explicitly so the display stack can initialize before mounting rootfs.
  boot.initrd.extraFirmwarePaths = [
    "qcom/a630_sqe.fw"
    "qcom/a640_gmu.bin"
    "qcom/sm8150/xiaomi/nabu/a640_zap.mbn"
  ];

  # == Filesystems ============================================================
  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/linux";
    fsType = "ext4";
    options = [
      "rw"
      "errors=remount-ro"
      # The raw ext4 image is flashed into an already-sized GPT partition.
      # Grow only the filesystem to that partition, exactly like Fedora's
      # fstab; boot.growPartition would instead try to alter the device GPT.
      "x-systemd.growfs"
    ];
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-partlabel/esp";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  # == Firmware ===============================================================
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.xiaomi-nabu-firmware ];

  # == Qualcomm remoteproc services ==========================================
  # Match Fedora's nabu preset: Linux 6.17 provides the QRTR name service and
  # PD mapper in-kernel, while userspace only runs rmtfs and tqftpserv.
  systemd.services.rmtfs = {
    description = "Qualcomm remotefs service";
    before = [ "NetworkManager.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/dev/qcom_rmtfs_mem1";
    serviceConfig = {
      ExecStart = "${pkgs.rmtfs}/bin/rmtfs -r -P -s";
      Restart = "always";
      RestartSec = "1";
    };
  };

  systemd.services.tqftpserv = {
    description = "QRTR TFTP service";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.tqftpserv}/bin/tqftpserv";
      Restart = "always";
    };
  };

  # == Audio (quad speakers, CS35L41 amplifiers) ==============================
  environment.etc."alsa-ucm2/conf.d/sm8150/sm8150.conf".source =
    "${pkgs.nabu-alsa-ucm}/sm8150.conf";
  environment.etc."alsa-ucm2/Xiaomi/nabu/HiFi.conf".source =
    "${pkgs.nabu-alsa-ucm}/HiFi.conf";

  # == Quirks =================================================================
  # Force /dev/rtc symlink to rtc1 (pm8150 RTC keeps time when powered off)
  services.udev.extraRules = ''
    SUBSYSTEM=="rtc", KERNEL=="rtc1", SYMLINK+="rtc", OPTIONS+="link_priority=10"
  '';

  # ath10k_snoc hangs the platform on warm reboot if not unloaded first
  systemd.services.ath10k-shutdown = {
    description = "Nabu - Disable WiFi Modules on Shutdown";
    after = [
      "network-online.target"
      "graphical.target"
    ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/true";
      ExecStop = "${pkgs.kmod}/bin/rmmod ath10k_snoc ath10k_core";
    };
  };

  # == Networking =============================================================
  networking.networkmanager = {
    enable = true;
    wifi.backend = "iwd";
  };
  networking.wireless.enable = false; # avoid wpa_supplicant conflict

  # == Zram (matches reference: full-RAM size, zstd) ==========================
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100;
  };

  # == Power ==================================================================
  powerManagement.enable = true;
}

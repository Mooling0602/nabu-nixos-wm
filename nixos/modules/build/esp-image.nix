# Complete, unprivileged ESP packaging for systemd-boot (no UKI, no rEFInd).
#
# systemd-boot installs to the removable fallback /EFI/BOOT/BOOTAA64.EFI
# (Project Aloha has no NVRAM variables); its loader entries reference the
# kernel/initrd/DTB under /nixos on the ESP.  Extra EFI files and menu entries
# come from the same configuration used by nixos-rebuild, including the
# rotation driver and Android stub.
#
# This is a build-time artifact module: it only defines system.build.esp-image
# and is not needed on the running device.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  config.system.build.esp-image =
    let
      extraFiles = lib.concatStringsSep "\n" (
        lib.mapAttrsToList
          (
            destination: source:
              ''
                install -Dm644 ${
                  lib.escapeShellArg (toString source)
                } ${lib.escapeShellArg "stage/${destination}"}
              ''
          )
          config.boot.loader.systemd-boot.extraFiles
      );
      extraEntries = lib.concatStringsSep "\n" (
        lib.mapAttrsToList
          (
            name: content:
              ''
                install -Dm644 ${
                  pkgs.buildPackages.writeText name content
                } ${lib.escapeShellArg "stage/loader/entries/${name}"}
              ''
          )
          config.boot.loader.systemd-boot.extraEntries
      );
      systemdBoot = "${config.systemd.package}/lib/systemd/boot/efi/systemd-bootaa64.efi";
      kernel = "${config.boot.kernelPackages.kernel}/${config.system.boot.loader.kernelFile}";
      initrd = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
      dtb = "${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}";
      init = "${config.system.build.toplevel}/init";
      kernelVersion = config.boot.kernelPackages.kernel.modDirVersion;
      kernelParams = lib.concatStringsSep " " config.boot.kernelParams;
      timeout = toString config.boot.loader.timeout;

      # Tools run on the build machine (buildPackages keeps cross builds
      # native); the deployed EFI binaries and kernel stay host-platform.
      buildPkgs = pkgs.buildPackages;
    in
    buildPkgs.runCommand "nabu-esp-image" {
      nativeBuildInputs = with buildPkgs; [
        dosfstools
        mtools
        zip
      ];
    } ''
      set -euo pipefail
      mkdir -p "$out" stage/EFI/BOOT stage/EFI/systemd stage/EFI/Android \
        stage/loader/entries stage/nixos

      # systemd-boot: removable fallback + vendor path.
      install -m644 ${systemdBoot} stage/EFI/BOOT/BOOTAA64.EFI
      install -m644 ${systemdBoot} stage/EFI/systemd/systemd-bootaa64.efi

      # Keep the image and on-device systemd-boot deployment in sync.
      ${extraFiles}
      ${extraEntries}

      # Kernel, initrd, device tree.
      install -m644 ${kernel} stage/nixos/kernel
      install -m644 ${initrd} stage/nixos/initrd
      install -m644 ${dtb} stage/nixos/nabu.dtb

      cat > stage/loader/loader.conf <<EOF
      timeout ${timeout}
      default nixos-nabu.conf
      console-mode keep
      EOF

      cat > stage/loader/entries/nixos-nabu.conf <<EOF
      title NixOS (nabu)
      version Generation 1, Linux ${kernelVersion}
      linux /nixos/kernel
      initrd /nixos/initrd
      options init=${init} ${kernelParams}
      devicetree /nixos/nabu.dtb
      sort-key nixos
      EOF

      # FAT timestamps cannot represent the Nix store's Unix epoch.
      find stage -exec touch -h -t 198001010000 {} +
      truncate -s 350105600 "$out/esp.img"
      mkfs.vfat --invariant -F 32 -S 4096 -s 1 -R 32 -h 21234176 \
        -n ESPNABU -i 5C7A09AD -f 2 "$out/esp.img"
      mcopy -m -i "$out/esp.img" -s stage/EFI ::/
      mcopy -m -i "$out/esp.img" -s stage/loader ::/
      mcopy -m -i "$out/esp.img" -s stage/nixos ::/
      fsck.fat -n "$out/esp.img"
      mdir -i "$out/esp.img" ::/EFI/BOOT/BOOTAA64.EFI
      mdir -i "$out/esp.img" ::/EFI/Android/Reboot2Android.efi
      mdir -i "$out/esp.img" ::/EFI/systemd/drivers/GopRotate_aa64.efi
      mdir -i "$out/esp.img" ::/nixos/nabu.dtb
      (cd stage && zip -qr "$out/efi-files.zip" EFI loader nixos)
    '';
}

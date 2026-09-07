{
  description = "NixOS WM configuration for Xiaomi Pad 5 (nabu)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    xwayland-satellite = {
      url = "git+https://github.com/Mooling0602/xwayland-satellite";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-flatpak.url = "github:gmodena/nix-flatpak";
  };

  outputs =
    inputs@{ self, nixpkgs, home-manager, nix-flatpak, xwayland-satellite, ... }:
    let
      lib = nixpkgs.lib;

      sharedModules = [
        {
          nixpkgs.overlays = [
            (import ./pkgs)
            # Expose the user's fork of xwayland-satellite as pkgs.xwayland-satellite,
            # overriding the nixpkgs one.  Mirrors dms-starter's flake.nix.
            (
              final: prev:
              {
                xwayland-satellite =
                  xwayland-satellite.packages.${final.stdenv.hostPlatform.system}.xwayland-satellite;
              }
            )
          ];
        }
        home-manager.nixosModules.home-manager
        nix-flatpak.nixosModules.nix-flatpak
        ./nixos/configuration.nix
      ];

      # Complete, unprivileged ESP packaging for systemd-boot (no UKI, no
      # rEFInd).  systemd-boot installs to the removable fallback
      # /EFI/BOOT/BOOTAA64.EFI (Project Aloha has no NVRAM variables); its
      # loader entries reference the kernel/initrd/DTB under /nixos on the ESP.
      # Extra EFI files and menu entries come from the same configuration used
      # by nixos-rebuild, including the rotation driver and Android stub.
      mkEsp =
        pkgs: cfg:
        let
          extraFiles = lib.concatStringsSep "\n" (lib.mapAttrsToList
            (destination: source: ''
              install -Dm644 ${lib.escapeShellArg (toString source)} ${lib.escapeShellArg "stage/${destination}"}
            '') cfg.boot.loader.systemd-boot.extraFiles);
          extraEntries = lib.concatStringsSep "\n" (lib.mapAttrsToList
            (name: content: ''
              install -Dm644 ${pkgs.writeText name content} ${lib.escapeShellArg "stage/loader/entries/${name}"}
            '') cfg.boot.loader.systemd-boot.extraEntries);
          systemdBoot = "${cfg.systemd.package}/lib/systemd/boot/efi/systemd-bootaa64.efi";
          kernel = "${cfg.boot.kernelPackages.kernel}/${cfg.system.boot.loader.kernelFile}";
          initrd = "${cfg.system.build.initialRamdisk}/${cfg.system.boot.loader.initrdFile}";
          dtb = "${cfg.hardware.deviceTree.package}/${cfg.hardware.deviceTree.name}";
          init = "${cfg.system.build.toplevel}/init";
          kernelVersion = cfg.boot.kernelPackages.kernel.modDirVersion;
          kernelParams = lib.concatStringsSep " " cfg.boot.kernelParams;
          timeout = toString cfg.boot.loader.timeout;
        in
        pkgs.runCommand "nabu-esp-image" {
          nativeBuildInputs = [ pkgs.dosfstools pkgs.mtools pkgs.zip ];
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

    in
    {
      # Native aarch64 configuration (build on the device / aarch64 builders)
      nixosConfigurations.nabu = lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = sharedModules;
      };

      packages =
        let
          # Cross-evaluated NixOS config: buildPlatform = current system,
          # hostPlatform = aarch64 (from hardware-nabu.nix).
          crossConfigFor =
            system:
            lib.nixosSystem {
              modules =
                [
                  {
                    nixpkgs.buildPlatform.system = system;
                  }
                ]
                ++ sharedModules;
            };
        in
        lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
          system:
          let
            pkgs = nixpkgs.legacyPackages.${system};
            cfg =
              if system == "aarch64-linux" then
                self.nixosConfigurations.nabu.config
              else
                (crossConfigFor system).config;
          in
          {
            # Bootable ESP image: systemd-boot + kernel + initrd + DTB + Android.
            nabu-esp = mkEsp pkgs cfg;
            # kernel alone (use .configfile passthru to inspect the config)
            nabu-kernel = cfg.system.build.kernel;
            # Flashable ext4 image from the same cross-evaluated configuration
            # as the ESP, so both artifacts reference the same system closure.
            nabu-rootfs = cfg.system.build.rootfs-image;
            default = self.packages.${system}.nabu-esp;
          }
        );
    };
}

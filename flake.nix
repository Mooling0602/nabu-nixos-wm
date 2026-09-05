{
  description = "NixOS for Xiaomi Pad 5 (nabu)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;

      sharedModules = [
        {
          nixpkgs.overlays = [ (import ./pkgs) ];
        }
        ./nixos/configuration.nix
      ];

      # The UKI is now produced by nixpkgs' boot.uki module (see nixos/uki.nix):
      # kernel + initrd + DTB + cmdline in one EFI PE, with the DTB embedded
      # via hardware.deviceTree.  The derivation is cfg.system.build.uki; here
      # we only package it into the ESP image below.

      # Complete, unprivileged ESP packaging.  A UKI alone is not a replacement
      # for the existing dualboot ESP: retain its rEFInd and Android entry.
      mkEsp = pkgs: uki: ukiFile:
        let
          dualboot = pkgs.fetchFromGitHub {
            owner = "hybrid-orbital";
            repo = "nabu_fedora_packages";
            rev = "cee0eec4d4f8681bf6fe423ff51904a649340ecd";
            sha256 = "0llfds8a1dfn9qldg6gf4kp50mnpb619vwf91bw08cqsabnsyhm3";
          };
        in
        pkgs.runCommand "nabu-esp-image" {
          nativeBuildInputs = [ pkgs.dosfstools pkgs.mtools pkgs.zip ];
        } ''
          mkdir -p "$out" stage/EFI/nixos
          cp -r ${dualboot}/nabu-fedora-dualboot-efi/boot/efi/EFI/{BOOT,Android} stage/EFI/
          chmod -R u+w stage
          cp ${uki}/${ukiFile} stage/EFI/nixos/nabu.efi
          # Stable explicit entry, independent of rEFInd's automatic scan.
          cat >> stage/EFI/BOOT/refind.conf <<'ENTRY'

          menuentry "NixOS (nabu)" {
              loader /EFI/nixos/nabu.efi
              icon /EFI/BOOT/icons/os_linux.png
          }
          ENTRY
          # FAT timestamps cannot represent the Nix store's Unix epoch.
          find stage -exec touch -h -t 198001010000 {} +
          truncate -s 350105600 "$out/esp.img"
          mkfs.vfat --invariant -F 32 -S 4096 -s 1 -R 32 -h 21234176 \
            -n ESPNABU -i 5C7A09AD -f 2 "$out/esp.img"
          mcopy -m -i "$out/esp.img" -s stage/EFI ::/
          fsck.fat -n "$out/esp.img"
          mdir -i "$out/esp.img" ::/EFI/BOOT/bootaa64.efi
          mdir -i "$out/esp.img" ::/EFI/Android/Reboot2Android.efi
          mcopy -i "$out/esp.img" ::/EFI/nixos/nabu.efi copied.efi
          cmp ${uki}/${ukiFile} copied.efi
          (cd stage && zip -qr "$out/efi-files.zip" EFI)
        '';

    in
    {
      # Native aarch64 configuration (build on the device / aarch64 builders)
      nixosConfigurations.nabu = lib.nixosSystem {
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
            # Single-file EFI kernel image — drop into ESP to test on device
            nabu-uki = cfg.system.build.uki;
            nabu-esp = mkEsp pkgs cfg.system.build.uki cfg.system.boot.loader.ukiFile;
            # kernel alone (use .configfile passthru to inspect the config)
            nabu-kernel = cfg.system.build.kernel;
            # Flashable ext4 image from the same cross-evaluated configuration
            # as the UKI, so both artifacts reference the same system closure.
            nabu-rootfs = cfg.system.build.rootfs-image;
            default = self.packages.${system}.nabu-uki;
          }
        );
    };
}

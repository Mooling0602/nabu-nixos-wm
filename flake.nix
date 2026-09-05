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

      /*
        Unified Kernel Image: Linux Image + initramfs + nabu DTB + kernel
        command line packed into a single EFI PE binary, bootable by the
        device's UEFI firmware (via the rEFInd dualboot setup).

        Drop the .efi into the ESP (e.g. EFI/nixos/) to boot/test.
      */
      mkUki =
        {
          kernel,
          initrd,
          cmdline,
          kernelVersion ? (kernel.version or "6.17.0-sm8150"),
          # build-host packages: ukify runs natively
          pkgs,
          # target-arch packages: aarch64 systemd provides the aa64 EFI stub
          targetPkgs,
        }:
        pkgs.stdenv.mkDerivation {
          pname = "nabu-uki";
          version = kernelVersion;

          passAsFile = [ "cmdlineText" "osReleaseText" ];
          cmdlineText = cmdline;
          # ukify defaults to reading /usr/lib/os-release, which does not exist
          # in the build environment (nixos/nix container); provide one
          # explicitly so the UKI .osrel section can be populated.
          osReleaseText = ''
            ID=nixos
            NAME="NixOS"
            PRETTY_NAME="NixOS ${kernelVersion} (Xiaomi Pad 5 / nabu)"
          '';

          nativeBuildInputs = [
            (pkgs.systemd.override { withUkify = true; })
          ];

          stub = "${targetPkgs.systemd}/lib/systemd/boot/efi/linuxaa64.efi.stub";

          buildCommand = ''
            set -euo pipefail

            # nix does not pre-create output dirs; ukify needs $out to exist
            mkdir -p "$out"

            kernel="${kernel}"
            echo ">>> kernel store path: $kernel"

            # Locate the bootable kernel image
            KIMG=""
            for candidate in "$kernel/vmlinuz" "$kernel/Image" "$kernel/zImage" "$kernel/bzImage"; do
              if [ -e "$candidate" ]; then KIMG="$candidate"; break; fi
            done
            if [ -z "$KIMG" ]; then
              echo "ERROR: no bootable kernel image found in $kernel" >&2
              ls -la "$kernel" >&2
              exit 1
            fi
            echo ">>> kernel image: $KIMG"

            # Locate the nabu DTB
            DTB="$(find "$kernel/dtbs" -name 'sm8150-xiaomi-nabu.dtb' -print -quit || true)"
            if [ -z "$DTB" ]; then
              echo "ERROR: sm8150-xiaomi-nabu.dtb not found under $kernel/dtbs" >&2
              find "$kernel" -name '*.dtb' >&2 || true
              exit 1
            fi
            echo ">>> dtb: $DTB"

            CMDLINE="$(cat "$cmdlineTextPath")"
            echo ">>> cmdline: $CMDLINE"
            case " $CMDLINE " in
              *" init=/nix/store/"*) ;;
              *)
                echo "ERROR: UKI command line has no NixOS init= closure" >&2
                exit 1
                ;;
            esac

            ukify build \
              --linux="$KIMG" \
              --initrd="${initrd}/initrd" \
              --devicetree="$DTB" \
              --cmdline="$CMDLINE" \
              --os-release="@$osReleaseTextPath" \
              --stub="$stub" \
              --output="$out/nabu-${kernelVersion}.efi"

            # convenience: stable filename for direct ESP deployment
            ln -s "nabu-${kernelVersion}.efi" "$out/nabu.efi"
            printf '%s\n' "$CMDLINE" > "$out/cmdline"

            ls -la "$out"
          '';

          meta = {
            description = "UKI (EFI) boot image for Xiaomi Pad 5 (nabu)";
            platforms = lib.platforms.linux;
          };
        };

      ukiFromConfig =
        cfg: pkgs:
        let
          # Keep the store path text in the command line without making the
          # UKI derivation build the entire userspace closure.  nabu-rootfs is
          # the output that materializes that matching closure.
          initPath = builtins.unsafeDiscardStringContext "${cfg.system.build.toplevel}/init";
        in
        mkUki {
          inherit pkgs;
          kernel = cfg.system.build.kernel;
          initrd = cfg.system.build.initialRamdisk;
          # NixOS stage-1 requires an explicit system closure.  Normal NixOS
          # boot loaders add this themselves; our hand-built UKI must do it.
          cmdline = lib.concatStringsSep " " ([ "init=${initPath}" ] ++ cfg.boot.kernelParams);
          # aarch64 stub source: native on aarch64 hosts, cross on x86_64
          targetPkgs =
            if pkgs.stdenv.hostPlatform.isAarch64 then pkgs else pkgs.pkgsCross.aarch64-multiplatform;
        };

      # Complete, unprivileged ESP packaging.  A UKI alone is not a replacement
      # for the existing dualboot ESP: retain its rEFInd and Android entry.
      mkEsp = pkgs: uki:
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
          cp ${uki}/nabu.efi stage/EFI/nixos/nabu.efi
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
          cmp ${uki}/nabu.efi copied.efi
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
            nabu-uki = ukiFromConfig cfg pkgs;
            nabu-esp = mkEsp pkgs self.packages.${system}.nabu-uki;
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

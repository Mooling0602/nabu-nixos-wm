[English](README.md) | [简体中文](README_zh_CN.md)

# NixOS for Nabu

NixOS for Xiaomi Pad 5 (nabu), booted as a UEFI Unified Kernel Image (UKI) — compatible with the [nabu_fedora](https://github.com/jhuang6451/nabu_fedora) dualboot setup.

## How it works

```
UEFI firmware (Project Aloha / DBKP)
  └─ rEFInd (on ESP partition)
       └─ nabu-<version>.efi   ← Unified Kernel Image built by this flake
            ├─ Linux 6.17 (sm8150-mainline + nabu drivers)
            ├─ initramfs (generic, UFS drivers forced in)
            ├─ sm8150-xiaomi-nabu.dtb
            └─ cmdline: root=PARTLABEL=linux ...
                  └─ ext4 rootfs on the `linux` partition
```

* **Kernel**: mainline 6.17 from the [sm8150-mainline](https://gitlab.com/sm8150-mainline/linux) project, with the same config fragments as the reference Fedora build.
* **UKI output**: a single `.efi` file for your ESP (`EFI/nixos/`). Its `init=` references a specific NixOS system closure: deploy the matching rootfs, or ensure that exact closure already exists on the device.
* **Qualcomm userspace**: Fedora-aligned `rmtfs` / `tqftpserv`, ALSA UCM profiles for the quad speakers, a pm8150 RTC udev rule, and an ath10k shutdown workaround. The QRTR name service and PD mapper are provided by the kernel.
* **Firmware**: redistributable Qualcomm firmware via `hardware.enableRedistributableFirmware` + device-specific files (adsp/modem/venus/cirrus/novatek) packaged from the postmarketOS firmware repo.

## Build

On any Linux machine with Nix (flakes enabled):

```Shell
# The EFI kernel image (works from x86_64 — cross-compiles)
nix build .#nabu-uki
# → result/nabu-<version>.efi

# Matching ext4 rootfs (also cross-builds on x86_64)
nix build .#nabu-rootfs
# → result/nabu-rootfs.ext4.img

# Complete ESP: reference rEFInd + Android entry + NixOS UKI
nix build .#nabu-esp
# → result/esp.img and result/efi-files.zip

# Export matching images and SHA256SUMS into a new result-images/build-* folder
bash scripts/build-image.sh
```

> [!TIP]
> On x86_64, use `nix build .#nabu-uki` / `nix build .#nabu-rootfs`; they use an x86_64 build platform and an aarch64 host platform, without binfmt/QEMU. Do not select the native aarch64 output with `--system aarch64-linux` unless a remote aarch64 builder is configured.

## Test on your device (dualboot with Android/Fedora already installed)

1. Copy the UKI to the ESP:
   ```Shell
   # from the running Linux system on the tablet:
   sudo mkdir -p /boot/efi/EFI/nixos
   sudo cp result/nabu-*.efi /boot/efi/EFI/nixos/
   ```
   (or mount the ESP on your PC and copy there)
2. Reboot; select the `nabu` entry in rEFInd.
3. The matching NixOS rootfs must be on the `linux` partition. A Fedora rootfs cannot satisfy the UKI's NixOS `init=` path.

## QEMU smoke test and flashing

On x86_64, use the shipped kernel/initrd with QEMU's `virt` hardware:

```sh
nix shell --inputs-from . nixpkgs#qemu nixpkgs#util-linux nixpkgs#e2fsprogs \
  nixpkgs#pkgsCross.aarch64-multiplatform.stdenv.cc.bintools \
  -c bash scripts/qemu-smoke.sh \
  result-images/build-XXXXXX/nabu.efi \
  result-images/build-XXXXXX/nabu-rootfs.ext4.img \
  result-images/build-XXXXXX/esp.img
```

The script creates a disposable GPT disk with 4 KiB sectors and `esp`/`linux`
labels, copies both images, and adds only the QEMU serial console to the UKI
command line. Its temporary directory contains the serial log. Login is automatic
as `nabu`; the initial sudo password is `nabu`. Check `systemctl --failed`,
`sudo nix-store --verify --check-contents`, and `findmnt /boot/efi`, then
`sudo poweroff`. This tests initrd, rootfs, activation, filesystem growth and
userspace. QEMU uses its own DTB: nabu's UEFI, UFS, display, touch, audio and
Qualcomm firmware still require hardware testing.

For devices already configured with the reference UEFI/dualboot partition layout,
verify `SHA256SUMS` and use the uncompressed images:

```sh
sha256sum -c SHA256SUMS
fastboot flash linux nabu-rootfs.ext4.img
fastboot flash esp esp.img
fastboot reboot
```

Flashing replaces the existing Linux filesystem and ESP contents; back them up
first. `esp.img` is 350105600 bytes and contains the reference rEFInd/Android
files plus NixOS. `nabu.efi` is a UKI to copy into an existing ESP, not a raw
partition image. Change the initial password after first boot.

## Status

- [x] Flake scaffolding: `nixosConfigurations.nabu`, cross-buildable UKI output
- [x] Kernel 6.17.0-sm8150 packaged (fragment-merged config, reproducible)
- [x] Device packages: `pd-mapper`, `xiaomi-nabu-firmware`, ALSA UCM
- [x] Qualcomm service stack in NixOS config
- [x] Flashable ext4 rootfs image (`nix build .#nabu-rootfs` or `scripts/build-image.sh rootfs`)
- [ ] First real device boot
- [ ] CI (GitHub Actions) builds
- [ ] Desktop environment variant (niri/GNOME/KDE)

## References & credits

* [jhuang6451/nabu_fedora](https://github.com/jhuang6451/nabu_fedora) — the reference implementation this project mirrors (kernel config, UKI layout, services, quirks)
* [sm8150-mainline/linux](https://gitlab.com/sm8150-mainline/linux) — mainline kernel for SM8150 devices
* [Project-Aloha](https://github.com/Project-Aloha) — UEFI firmware for nabu
* [map220v](https://github.com/map220v), [timoxa0](https://github.com/timoxa0), [nik012003](https://github.com/nik012003), [panpantepan](https://gitlab.com/panpanpanpan) and the nabu Linux community
* Firmware: [nabu-firmware (postmarketOS)](https://gitlab.postmarketos.org/panpanpanpan/nabu-firmware)

## License

MIT — see [LICENSE](LICENSE). Kernel sources are GPLv2; firmware files remain under their original licenses.

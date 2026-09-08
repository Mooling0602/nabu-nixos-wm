**English** | [简体中文](README_zh_CN.md)

# Nabu NixOS WM

A buildable, updatable NixOS WM desktop configuration for the **Xiaomi Pad 5 (nabu)**.
The current boot method uses **systemd-boot with separate kernel, initrd and device tree
files** and provides a native NixOS generation boot menu, with **niri** as the window
manager and the foundation of the desktop environment.

This project continues the porting work of
[hybrid_orbital/nixos-for-nabu](https://github.com/hybrid-orbital/nixos-for-nabu).
The original repository established the NixOS configuration, the kernel and device
packages, bootable NixOS images and the infrastructure to build them; this branch builds
on that foundation with validation, native Nixpkgs boot management and everyday desktop
use. This project depends on the work and contributions of many other projects; see the
acknowledgements below.

## Configuration

### Package management

nix flake + home-manager

### Desktop environment

Niri + Noctalia

### Hardware limitations

| Area | Current limitation |
| --- | --- |
| Camera | Not working |
| Low-power suspend | Not working; locking or blanking the display does not establish low-power operation |
| Power key | Deliberately ignored pending usable screen-off and suspend/resume support |
| Boot reliability | Boot sometimes fails; the cause is still under investigation |
| Wi-Fi MAC address | A new random address is selected on every reboot; it does not remain stable across boots |
| Wi-Fi hangs after idle | After long idle, ath10k_snoc detects an unresponsive firmware/WMI, recovery fails repeatedly, and Wi-Fi stops working until the driver is reloaded |
| Image size | The rootfs is large; reducing the closure and splitting configurations are priorities |

The changing Wi-Fi MAC address may affect MAC-based DHCP reservations and network access
rules. The behavior is confirmed, but its cause and a fix have not been verified. Other
hardware needs fuller test records; enabling a driver in the configuration is not evidence
of hardware validation. When reporting a problem, include the image version, firmware
version, reproduction steps and logs; distinguish cold boots from warm reboots.

Wi-Fi may hang after a long idle period: `ath10k_snoc` (WCN3990) detects an
unresponsive firmware/WMI, attempts automatic recovery, and after repeated
failures gives up (wedged state), leaving Wi-Fi unusable. The `WARN_ON` in
`mac.c` seen in dmesg is the result of the failed recovery, not the root cause.
The root cause is still under investigation and is suspected to relate to SNOC
power management / WMI timeouts, not the firmware version (firmware is loaded
via TQFTP and is already HL 3.2.0). Reload the driver manually to recover:

```sh
# Option 1 (recommended): rebind the platform device, no extra tools needed
ls /sys/bus/platform/drivers/ath10k_snoc/          # check the device name (usually 18800000.wifi)
nmcli radio wifi off
echo 18800000.wifi | sudo tee /sys/bus/platform/drivers/ath10k_snoc/unbind
echo 18800000.wifi | sudo tee /sys/bus/platform/drivers/ath10k_snoc/bind
nmcli radio wifi on

# Option 2: unload/reload the kernel module (modprobe is not on the default PATH; run `nix shell nixpkgs#kmod` first)
sudo systemctl stop NetworkManager
sudo modprobe -r ath10k_snoc
sudo modprobe ath10k_snoc
sudo systemctl start NetworkManager
```

Restarting NetworkManager alone does not recover; the driver must be re-probed
(unbind/bind or module reload).

## Important notes

At the Noctalia greeter, both the default username and initial password are **`nabu`**.
Run `passwd` after login. **TTY autologin and SSH password authentication are also
enabled**; adjust the configuration for ongoing personal use. Changing the password does
not disable TTY autologin. Use `systemctl --failed` to inspect failed services,
`findmnt /boot/efi` to check the ESP mount, and `bootctl list` to inspect boot entries.

To preserve data from an existing NixOS installation, avoid flashing the rootfs.
Back up first, then deploy and verify the new boot entry with an on-device
`nixos-rebuild boot`. See the [installation guide](docs/installation.md) for full
migration and first-boot details.

## Boot and generations

```text
Project Aloha UEFI / existing DBKP boot environment
  → systemd-boot (EFI/BOOT/BOOTAA64.EFI)
    → NixOS generation
      → matching kernel + initrd + external DTB + init=<generation>/init
        → ext4 rootfs → Noctalia greeter → niri
    → Android entry
```

NixOS manages boot deployment on the device with `boot.loader.systemd-boot.enable = true`
and `installDeviceTree = true`; unchanged boot files can be reused across generations.
There is no per-generation UKI to package, no `nabu-previous.efi` to maintain, and no
mutable system profile shared by all boot entries. Each entry's `init=` points to that
generation's specific Nix store system closure, and old generations retain their matching
boot files, so an earlier system configuration can be restored from the menu. External
DTB loading has been verified in the current firmware environment with Secure Boot
disabled; a UKI is no longer necessary to deliver the device tree.

The project's `mkEsp` code still assembles the initial ESP with one generation.
Subsequent rebuilds use the nixpkgs systemd-boot installer to deploy and manage
generations. Initial image files and old UKI/rEFInd files may not be cleaned up
automatically; check retained entries before deleting them. See
[architecture](docs/architecture.md) for implementation details.

## On-device updates and rollback

Keep a copy of the repository configuration on the tablet. You can create your own
configuration branch from this release:

> This repository itself was created exactly this way; the original project's
> instructions are kept here for reference.

```sh
git clone https://github.com/hybrid-orbital/nixos-for-nabu.git
cd nixos-for-nabu
git switch -c my-nabu v0.1.0-alpha
```

After editing, use `git add` for new files so the Git flake can read them; a commit
is not required. Update from the checkout:

```sh
sudo nixos-rebuild switch --flake .#nabu
```

`switch` updates the boot menu and activates the configuration; kernel, initrd and
boot-parameter changes take effect after a reboot. Use
`sudo nixos-rebuild boot --flake .#nabu` to prepare only the next boot. `flake.lock`
pins dependency versions; ordinary rebuilds do not upgrade them. Run
`nix flake update` and build to verify when you intend to update inputs.

If the system is still running, roll back to the previous generation with:

```sh
sudo nixos-rebuild switch --rollback
```

If a new generation fails to boot, select a retained older generation in the
systemd-boot menu (use the volume keys to choose an entry and the power key to confirm).
Manually selecting an older generation does not permanently roll back the system
profile; inspect and roll back or repair the configuration after booting.
**Generation rollback does not restore user files or databases.**

Sharing boot files reduces duplication, but distinct kernels and initrds still consume
ESP space. Set `boot.loader.systemd-boot.configurationLimit = 10;` in your configuration
to limit menu generations; it does not automatically delete historical systems from the
Nix store. Keep a verified bootable generation before cleanup. See
[on-device usage and rollback](docs/usage-on-device.md) for details.

## Build

> This repository is mainly for daily use, so there is usually no need to rebuild the
> kernel or the rootfs unless reinstalling. The original project's build information is
> kept here for reference.

On a Linux/Nix environment with flakes enabled, check out the repository as shown above,
then run from the repository root:

```sh
# Build both outputs together; keep the source, flake.lock and local configuration consistent.
nix build .#nabu-esp .#nabu-rootfs

# Export esp.img, efi-files.zip, the rootfs and SHA256SUMS to a fresh directory.
# This script has not been tested; copying the nix build outputs manually
# to a location of your choice is recommended for now.
bash scripts/build-image.sh
```

The only current NixOS configuration, `nixosConfigurations.nabu`, includes niri +
Noctalia. `nabu-esp`, `nabu-rootfs` and `nabu-kernel` have `x86_64-linux` and
`aarch64-linux` outputs; the default output is the ESP. The export script writes to a
fresh `result-images/build-*` directory and refuses to overwrite same-named artifacts.
Build the ESP and rootfs together; do not mix artifacts from different commits,
configurations or native/cross builds. Keep the working tree and lock file unchanged
during the build, and prepare enough disk space, memory and dependency caches or network
access.

**Cross-build caveat:** x86_64 → aarch64 and native aarch64 builds have different
`buildPlatform` values and dependency graphs, normally producing different derivations
and store paths. Even after a cross-built image boots successfully, the first native
rebuild may rebuild the kernel and many packages; existing cross-built artifacts are not
guaranteed to hit the native cache. This follows from different build inputs, not merely
changing machines; matching existing outputs and native caches can still be reused.
Cross compilation may also fail due to package or toolchain compatibility. Successful
evaluation is not proof of a successful build or hardware boot. `--system aarch64-linux`
only selects the native ARM64 outputs; it does not configure cross compilation. Those
outputs require an ARM64 builder, a matching cache or configured emulation.

The flake currently produces an uncompressed rootfs; the zstd compression and split
archives in releases are additional packaging steps at release time. Compression reduces
download size, not the system closure installed on the device. The old
`scripts/qemu-smoke.sh` has not been adapted to the current non-UKI outputs and cannot
serve as the test entry point for this version. See the [build guide](docs/building.md)
for more troubleshooting and measurement methods.

## Further reading

- [Installation, release images and first boot](docs/installation.md)
- [Builds, cross compilation and caches](docs/building.md)
- [Boot architecture and generations](docs/architecture.md)
- [On-device updates, rollback and cleanup](docs/usage-on-device.md)
- [niri + Noctalia desktop](docs/desktop.md)
- [Device status](docs/device-status.md) · [Boot logging diagnostics](docs/boot-logging.md)
- [Roadmap](docs/roadmap.md) · [Contributing](CONTRIBUTING.md)
- [Project history, upstream and credits](docs/history.md)

## Acknowledgements

Thank you to [Mooling0602](https://github.com/Mooling0602) for providing the
configuration skeleton, the particularly important kernel and firmware packages, the
rootfs images, and the early boot and display adaptation for NixOS on the Xiaomi Pad 5;
and to [hybrid_orbital](https://github.com/hybrid-orbital) for the later reorganization,
refinement and optimization. The current system configuration builds on these
achievements. The community rEFInd + UKI approach provided a convenient starting point
for further building, debugging and hardware validation.

Linux on nabu also depends on sustained community work on firmware, kernels, device
services and desktop support:

- [Mooling0602/nixos-for-nabu](https://github.com/Mooling0602/nixos-for-nabu): the original NixOS port and image foundation.
- [hybrid_orbital/nixos-for-nabu](https://github.com/hybrid-orbital/nixos-for-nabu): a refined NixOS port with image flashing and everyday management and usage.
- [Mooling0602/nabu-nixos-kde-config](https://github.com/Mooling0602/nabu-nixos-kde-config): related NixOS experiments on nabu (rather messy, planned to be archived soon).
- [Mooling0602/dms-starter](https://github.com/Mooling0602/dms-starter): a complete NixOS PC desktop configuration based on DankMaterialShell, targeting x86_64 and multi-device management (aarch64 support is also planned soon).
- [jhuang6451/nabu_fedora](https://github.com/jhuang6451/nabu_fedora): image, kernel configuration, device service and hardware adaptation references.
- [nabu_fedora_packages](https://github.com/jhuang6451/nabu_fedora_packages): device packages and boot resources; this repository pins the corresponding resource fork's revision and hash in `boot.nix`.
- [sm8150-mainline/linux](https://gitlab.com/sm8150-mainline/linux): SM8150 mainline kernel work.
- [Project Aloha](https://github.com/Project-Aloha/mu_aloha_platforms): the device UEFI firmware.
- [rodriguezst/nabu-dualboot-img](https://github.com/rodriguezst/nabu-dualboot-img): nabu dual-boot work.
- [GopRotate](https://github.com/apop2/GopRotate): the EFI display rotation driver.
- [nabu-firmware](https://gitlab.postmarketos.org/panpanpanpan/nabu-firmware): the device firmware packaging source.
- [NixOS / nixpkgs](https://github.com/NixOS/nixpkgs) and [systemd](https://github.com/systemd/systemd): the configuration system and native boot management.
- [niri](https://github.com/niri-wm/niri) and [Noctalia](https://github.com/noctalia-dev/noctalia-shell): the current desktop and shell.
- map220v, timoxa0, nik012003, panpantepan, and the community contributors who continue to adapt and test Linux on nabu.

See [project history](docs/history.md) for a more complete evolution record.

## License

Project configuration and scripts are MIT-licensed; see [LICENSE](LICENSE).
The kernel, firmware, EFI programs and other third-party components retain their
respective licenses.

[English](README.md) | [简体中文](README_zh_CN.md)

# NixOS for Nabu（小米平板 5）

以 UEFI Unified Kernel Image（UKI）方式启动的小米平板 5（nabu）NixOS —— 与 [nabu_fedora](https://github.com/jhuang6451/nabu_fedora) 双系统方案完全兼容。

## 工作原理

```
UEFI 固件（Project Aloha / DBKP）
  └─ rEFInd（ESP 分区）
       └─ nabu-<version>.efi   ← 本 flake 构建的 Unified Kernel Image
            ├─ Linux 6.17（sm8150-mainline + nabu 驱动）
            ├─ initramfs（通用镜像，强制包含 UFS 驱动）
            ├─ sm8150-xiaomi-nabu.dtb
            └─ cmdline: root=PARTLABEL=linux ...
                  └─ `linux` 分区上的 ext4 根文件系统
```

* **内核**：来自 [sm8150-mainline](https://gitlab.com/sm8150-mainline/linux) 项目的 mainline 6.17，配置片段与参考 Fedora 构建一致。
* **UKI 产物**：放入 ESP（`EFI/nixos/`）的单个 `.efi` 文件。其 `init=` 指向一个确定的 NixOS 系统闭包；必须部署配套 rootfs，或确保设备上已存在该闭包。
* **高通用户态服务**：与 Fedora 预设一致的 `rmtfs` / `tqftpserv`，四扬声器 ALSA UCM 配置，pm8150 RTC udev 规则，以及关机时卸载 ath10k 的规避服务。QRTR 名称服务和 PD mapper 由内核提供。
* **固件**：可再分发的高通固件（`hardware.enableRedistributableFirmware`）+ 设备专属文件（adsp/modem/venus/cirrus/novatek，来自 postmarketOS 固件仓库）。

## 构建

任何装了 Nix（启用 flakes）的 Linux 机器：

```Shell
# EFI 内核镜像（x86_64 上可交叉编译）
nix build .#nabu-uki
# → result/nabu-<version>.efi

# 与 UKI 配套的 ext4 rootfs（同样在 x86_64 上交叉构建）
nix build .#nabu-rootfs
# → result/nabu-rootfs.ext4.img

# 完整 ESP：参考 rEFInd + Android 入口 + NixOS UKI
nix build .#nabu-esp
# → result/esp.img 和 result/efi-files.zip

# 将配套镜像和 SHA256SUMS 导出到新的 result-images/build-* 目录
bash scripts/build-image.sh
```

> [!TIP]
> 在 x86_64 上请使用上面的 `nix build .#nabu-uki` / `nix build .#nabu-rootfs`；它们使用 x86_64 build platform 和 aarch64 host platform，不需要 binfmt/QEMU。不要用 `--system aarch64-linux` 构建原生 aarch64 输出，除非已经配置远程 aarch64 构建机。

## 在设备上测试（已装 Android/Fedora 双系统）

1. 把 UKI 复制进 ESP：
   ```Shell
   # 在平板上运行的 Linux 系统里执行：
   sudo mkdir -p /boot/efi/EFI/nixos
   sudo cp result/nabu-*.efi /boot/efi/EFI/nixos/
   ```
   （也可以在 PC 上挂载 ESP 分区复制）
2. 重启，在 rEFInd 里选择 `nabu` 启动项。
3. `linux` 分区必须装有配套的 NixOS rootfs；Fedora rootfs 中没有 UKI 所需的 NixOS `init=` 路径。

## QEMU 验证与刷机

在 x86_64 上，用实际发布的内核和 initrd 启动 QEMU `virt`：

```sh
nix shell --inputs-from . nixpkgs#qemu nixpkgs#util-linux nixpkgs#e2fsprogs \
  nixpkgs#pkgsCross.aarch64-multiplatform.stdenv.cc.bintools \
  -c bash scripts/qemu-smoke.sh \
  result-images/build-XXXXXX/nabu.efi \
  result-images/build-XXXXXX/nabu-rootfs.ext4.img \
  result-images/build-XXXXXX/esp.img
```

脚本在临时目录创建 4 KiB 扇区、带 `esp` / `linux` 标签的 GPT 测试磁盘，
复制两个镜像，仅向 UKI 参数追加 QEMU 串口；串口日志保存在该临时目录。
自动登录用户为 `nabu`，初始 sudo 密码为 `nabu`。可检查 `systemctl --failed`、
`sudo nix-store --verify --check-contents` 和 `findmnt /boot/efi`，最后执行
`sudo poweroff`。这会验证 initrd、rootfs、系统激活、扩容和用户空间。
QEMU 使用自己的 DTB；nabu 的 UEFI、UFS、显示、触摸、音频和高通固件仍需真机验证。

设备已安装参考方案的 UEFI、并配置好双系统分区时，在产物目录校验后刷入未压缩镜像：

```sh
sha256sum -c SHA256SUMS
fastboot flash linux nabu-rootfs.ext4.img
fastboot flash esp esp.img
fastboot reboot
```

刷写会替换已有 Linux 文件系统和 ESP 内容，请先备份。`esp.img` 为 350105600 字节，
包含参考 rEFInd / Android 文件及 NixOS。`nabu.efi` 是复制到现有 ESP 的 UKI，
不能当作分区镜像直接刷写。首次启动后请修改初始密码。

## 进度

- [x] Flake 骨架：`nixosConfigurations.nabu`、可交叉构建的 UKI 产物
- [x] 内核 6.17.0-sm8150 打包（片段合并配置，可复现）
- [x] 设备软件包：`pd-mapper`、`xiaomi-nabu-firmware`、ALSA UCM
- [x] NixOS 配置中的高通服务栈
- [x] 可刷写的 ext4 rootfs 镜像（`nix build .#nabu-rootfs` 或 `scripts/build-image.sh rootfs`）
- [ ] 首次真机启动
- [ ] CI（GitHub Actions）构建
- [ ] 桌面环境变体（niri/GNOME/KDE）

## 参考与致谢

* [jhuang6451/nabu_fedora](https://github.com/jhuang6451/nabu_fedora) —— 本项目镜像参考的实现（内核配置、UKI 布局、服务、设备规避）
* [sm8150-mainline/linux](https://gitlab.com/sm8150-mainline/linux) —— SM8150 设备的 mainline 内核
* [Project-Aloha](https://github.com/Project-Aloha) —— nabu 的 UEFI 固件
* [map220v](https://github.com/map220v)、[timoxa0](https://github.com/timoxa0)、[nik012003](https://github.com/nik012003)、[panpantepan](https://gitlab.com/panpanpanpan) 与 nabu Linux 社区
* 固件：[nabu-firmware（postmarketOS）](https://gitlab.postmarketos.org/panpanpanpan/nabu-firmware)

## 许可

MIT —— 见 [LICENSE](LICENSE)。内核源码为 GPLv2；固件文件保留其原始许可。

[English](README.md) | **简体中文**

# Nabu NixOS WM

为小米平板 5（**nabu**）提供可构建、可更新的 NixOS WM 桌面配置。当前系统启动引导方式采用
**systemd-boot + 独立内核、initrd 和设备树**方案，并提供 NixOS 原生 generation 启动菜单，
使用**niri**作为窗口管理器和桌面环境基础。

本项目是 [hybrid_orbital/nixos-for-nabu](https://github.com/hybrid-orbital/nixos-for-nabu)
移植工作的延续。原仓库建立了 NixOS 配置、内核与设备软件包、可启动的NixOS镜像及其构建基础；
本分支在此基础上推进验证、Nixpkgs 原生启动管理和日常桌面使用。
本项目离不开诸多其它项目的工作与贡献。有关的项目与贡献者详见下方致谢。

## 配置内容

### 包管理

nix flake + home-manager

### 桌面环境

Niri + Noctalia

### 硬件缺陷

| 项目 | 当前限制 |
| --- | --- |
| 相机 | 尚不可用 |
| 低功耗休眠 | 尚不可用；锁屏、熄屏不等于进入低功耗状态 |
| 电源键 | 当前被刻意忽略，实用的熄屏、休眠和唤醒方案仍需适配 |
| 启动可靠性 | 偶尔启动失败，原因仍待排查 |
| Wi-Fi MAC 地址 | 每次重启都会随机选择新的地址，不能依赖跨重启保持固定 MAC |
| Wi-Fi 久置卡死 | 空闲较久后 ath10k_snoc 检测到固件/WMI 无响应并反复恢复失败，Wi-Fi 失效，需手动重载驱动 |
| 镜像体积 | 当前 rootfs 较大，缩减闭包与拆分配置是后续重点 |

Wi-Fi MAC 地址变化可能影响基于 MAC 的 DHCP 地址预留和网络准入规则；
目前仅确认这一现象，尚未确定原因或验证修复方法。其他硬件也需要更完整的测试记录，
不能仅凭配置中启用驱动就认为已经验证。报告问题时请附上镜像版本、固件版本、
重现步骤和日志；启动失败请区分冷启动与热重启。

Wi-Fi 在长时间空闲后可能卡死：`ath10k_snoc`（WCN3990）检测到固件/WMI 无响应后会尝试
自动恢复，连续失败后驱动放弃（进入 wedged 状态），Wi-Fi 不再可用。dmesg 中 `mac.c`
的 `WARN_ON` 是恢复失败后的结果，不是根因；根因目前仍在排查，疑似与 SNOC 电源管理 /
WMI 超时有关，与固件版本无关（固件经 TQFTP 加载，已是较新的 HL 3.2.0）。卡死后可
手动重载驱动恢复：

```sh
# 方法一（推荐）：重新绑定平台设备，不需要额外工具
ls /sys/bus/platform/drivers/ath10k_snoc/          # 确认设备名（通常为 18800000.wifi）
nmcli radio wifi off
echo 18800000.wifi | sudo tee /sys/bus/platform/drivers/ath10k_snoc/unbind
echo 18800000.wifi | sudo tee /sys/bus/platform/drivers/ath10k_snoc/bind
nmcli radio wifi on

# 方法二：卸载/重载内核模块
sudo systemctl stop NetworkManager
sudo modprobe -r ath10k_snoc
sudo modprobe ath10k_snoc
sudo systemctl start NetworkManager
```

仅重启 NetworkManager 无法恢复，必须让驱动重新 probe（unbind/bind 或重载模块）。

## 注意事项

进入 Noctalia 登录界面后，默认用户和初始密码均为 **`nabu`**，请登录后运行 `passwd`
修改密码。当前还启用了 **TTY 自动登录和 SSH 密码认证**，长期使用时应按需要修改配置；
修改密码不会关闭 TTY 自动登录。可用 `systemctl --failed` 检查失败服务，
`findmnt /boot/efi` 检查 ESP 挂载，`bootctl list` 检查启动项。

从旧安装保留数据迁移时不要直接刷写 rootfs；备份后使用设备上的 `nixos-rebuild boot`
部署并验证新启动入口。完整迁移与首次启动说明见[安装指南](docs/installation.md)。

## 启动与 generation

```text
Project Aloha UEFI / 现有 DBKP 启动环境
  → systemd-boot（EFI/BOOT/BOOTAA64.EFI）
    → 选择 NixOS generation
      → 对应内核 + initrd + 外部 DTB + init=<该代系统>/init
        → ext4 rootfs → Noctalia 登录界面 → niri 桌面
    → Android 启动入口
```

`boot.loader.systemd-boot.enable = true` 与 `installDeviceTree = true` 负责设备上的
启动部署；相同启动文件可以在各代之间复用。无需每代打包 UKI，也无需维护
`nabu-previous.efi` 或把所有启动项指向可变的 system profile。
每个条目的 `init=` 指向该代具体的 Nix store 系统闭包，旧代保留配套的启动文件，
因此可以从菜单恢复先前的系统配置。外部 DTB 已在当前关闭 Secure Boot 的固件环境验证可用，
UKI 不再是传递设备树的必要条件。

首次 ESP 仍由本项目的 `mkEsp` 逻辑组装，只有一个初始 generation；日常 rebuild 才由
nixpkgs 的 systemd-boot 安装器部署并管理各代。初始文件与旧 UKI/rEFInd 文件不一定会
被自动清理，手动删除前须确认没有保留的条目引用。更完整的实现见[技术说明](docs/architecture.md)。

## 设备上更新与回滚

在平板上保留仓库配置副本。可以从本次发布创建自己的配置分支：

> 实际上本仓库就是如此生成的，此处保留了原项目的内容方便参考。

```sh
git clone https://github.com/hybrid-orbital/nixos-for-nabu.git
cd nixos-for-nabu
git switch -c my-nabu v0.1.0-alpha
```

修改配置后，新文件需要先 `git add` 才能被 Git flake 读取，不必先提交。
从仓库目录更新：

```sh
sudo nixos-rebuild switch --flake .#nabu
```

`switch` 更新启动菜单并激活配置；内核、initrd 和启动参数的改变在重启后生效。
只准备下次启动可使用 `sudo nixos-rebuild boot --flake .#nabu`。
`flake.lock` 固定依赖版本，普通 rebuild 不会自动升级它们；需要更新输入时再运行
`nix flake update` 并构建验证。

系统仍能运行时，可回滚到前一代：

```sh
sudo nixos-rebuild switch --rollback
```

如果新代无法启动，在 systemd-boot 菜单选择保留的旧代 ( 你可以通过使用音量键来选择，按下电源键确认 )。手动选
择旧代不会自动把系统profile 永久回滚，进入系统后检查并回滚或修复配置。
**generation 回滚不会恢复用户文件或数据库。**

共享启动文件减少了重复占用，但不同内核和 initrd 仍会消耗 ESP 空间。可在配置中设置
`boot.loader.systemd-boot.configurationLimit = 10;` 限制菜单代数；它不会自动删除
Nix store 的历史系统。清理前保留已验证可启动的版本，具体方法见[设备使用与回滚](docs/usage-on-device.md)。

## 构建入口

> 本仓库主要是作为日常使用，一般无需再构建内核和 RootFS，除非需要重装。仍然保留原项目的相关信息以供参考。

在启用了 flakes 的 Linux/Nix 环境，按上面的命令检出仓库，从仓库目录运行：

```sh
# 配套构建；保持源码、flake.lock 与本地配置一致
nix build .#nabu-esp .#nabu-rootfs

# 导出 esp.img、efi-files.zip、rootfs 和 SHA256SUMS 到新的目录
# 尚未测试该脚本是否有效，建议手动拷贝 nix build 的产物到你喜欢的地方
bash scripts/build-image.sh
```

当前只有 `nixosConfigurations.nabu`，包含 niri + Noctalia。`nabu-esp`、
`nabu-rootfs`、`nabu-kernel` 提供 `x86_64-linux` 和 `aarch64-linux` 输出；默认输出为 ESP。
导出脚本默认写入新的 `result-images/build-*` 目录，并拒绝覆盖同名产物。
ESP 和 rootfs 必须配套构建，不能混用不同提交、配置或原生/交叉构建的产物。
构建期间保持工作树和 lock 不变，并准备足够磁盘、内存和依赖缓存或网络。

**交叉构建特别说明：** x86_64 → aarch64 与 aarch64 原生构建使用不同的
`buildPlatform` 和构建依赖，通常产生不同的 derivation/store 路径。交叉镜像在平板上
启动后，首次原生 rebuild 仍可能重新构建内核和大量包；已有交叉产物不能保证命中原生缓存。
这来自构建输入差异，不是更换机器本身改变 hash；已有匹配产物或原生缓存仍可复用。
交叉编译也可能因包或工具链适配问题失败，求值通过不代表构建或真机启动成功。
`--system aarch64-linux` 只选择原生 ARM64 输出，不会自动提供交叉编译能力；该输出
需要 ARM64 builder、匹配缓存或已配置的模拟环境。

当前 flake 输出未压缩 rootfs；release 中的 zstd 压缩与分卷是发布时的额外处理。
压缩只减少下载大小，不会缩减设备上的系统闭包。旧 `scripts/qemu-smoke.sh` 尚未适配
当前非 UKI 产物，不能作为本版本的测试入口。更多排障与测量方法见[构建指南](docs/building.md)。

## 进一步阅读

- [安装、发布镜像与首次启动](docs/installation.md)
- [构建、交叉编译与缓存](docs/building.md)
- [启动架构与 generation](docs/architecture.md)
- [设备上更新、回滚与清理](docs/usage-on-device.md)
- [niri + Noctalia 桌面](docs/desktop.md)
- [设备支持状态](docs/device-status.md) · [启动日志排查](docs/boot-logging.md)
- [路线图](docs/roadmap.md) · [贡献指南](CONTRIBUTING.md)
- [项目沿革、上游与致谢](docs/history.md)

## 致谢

感谢 [Mooling0602](https://github.com/Mooling0602) 为小米平板5 的 NixOS 移植工作提供了配置骨架、内核和固件软件包（这相当重要），到 rootfs 镜像、早期启动与显示适配，
更感谢 [hybrid_orbital](https://github.com/hybrid-orbital) 所进行的后期整理、完善与优化，
当前系统配置建立在这些成果之上。
来自社区的 rEFInd + UKI 方案为继续构建、调试和真机验证提供了方便的起点。

nabu 上的 Linux 也依赖多个社区持续推进固件、内核、设备服务与桌面支持：

- [Mooling0602/nixos-for-nabu](https://github.com/Mooling0602/nixos-for-nabu)：原始 NixOS 移植与镜像基础。
- [hybrid_orbital/nixos-for-nabu](https://github.com/hybrid-orbital/nixos-for-nabu)：完善的 NixOS 系统移植、镜像刷写与日常管理使用方案。 
- [Mooling0602/nabu-nixos-kde-config](https://github.com/Mooling0602/nabu-nixos-kde-config)：相关 nabu NixOS 实践尝试（但较为混乱，即将计划归档）
- [Mooling0602/dms-starter](https://github.com/Mooling0602/dms-starter)：基于 DankMaterialShell 的完整 NixOS PC 桌面配置，面向 x86_64 架构和多设备管理（也即将增加支持 aarch64 架构）
- [jhuang6451/nabu_fedora](https://github.com/jhuang6451/nabu_fedora)：镜像、内核配置、设备服务及硬件适配参考。
- [nabu_fedora_packages](https://github.com/jhuang6451/nabu_fedora_packages)：设备软件包及引导资源；本仓库在 nixos/modules/system/boot.nix 中固定了相应资源 fork 的版本与哈希。
- [sm8150-mainline/linux](https://gitlab.com/sm8150-mainline/linux)：SM8150 系列主线内核工作。
- [Project Aloha](https://github.com/Project-Aloha/mu_aloha_platforms)：设备 UEFI 固件。
- [rodriguezst/nabu-dualboot-img](https://github.com/rodriguezst/nabu-dualboot-img)：nabu 双系统启动工作。
- [GopRotate](https://github.com/apop2/GopRotate)：EFI 显示旋转驱动。
- [nabu-firmware](https://gitlab.postmarketos.org/panpanpanpan/nabu-firmware)：设备固件打包来源。
- [NixOS / nixpkgs](https://github.com/NixOS/nixpkgs)、[systemd](https://github.com/systemd/systemd)：配置系统与原生启动管理。
- [niri](https://github.com/niri-wm/niri)、[Noctalia](https://github.com/noctalia-dev/noctalia-shell)：当前桌面与 shell。
- map220v、timoxa0、nik012003、panpantepan，以及持续参与 nabu Linux 适配和测试的社区贡献者。

更完整的演进记录见[项目沿革](docs/history.md)。

## 许可

项目配置和脚本采用 MIT 许可，见 [LICENSE](LICENSE)。内核、固件、EFI 程序和其他
第三方组件保留各自许可；本仓库的许可不替代它们的许可。

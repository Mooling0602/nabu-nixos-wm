# 在设备上使用 nixos-rebuild（小米平板 5 / nabu）

刷机（esp + rootfs）完成后，日常系统更新直接在这台平板上用
`nixos-rebuild` 完成，**不需要再手动碰 ESP 里的 UKI**：每次
`nixos-rebuild boot|switch` 都会自动重建 UKI 并部署到
`/boot/efi/EFI/nixos/nabu.efi`（rEFInd 菜单项固定指向这个文件）。

## 前置条件

- 已按 README 完成刷机，rEFInd 菜单能进入 NixOS。
- 平板能联网（后续 rebuild 需要拉取 nixpkgs / 下载构建产物）。
- 平板上有这个 flake 仓库的拷贝。

## 首次准备：把 flake 放到设备上

```Shell
# 在 PC 上把仓库传到平板（平板已通过 USB 网络 / adb / ssh 可达）
rsync -av --delete ~/nixos-for-nabu/ nabu:/home/nabu/nixos-for-nabu/

# 平板侧
cd ~/nixos-for-nabu
```

> 注意：当前配置里 `nixpkgs.flake.setNixPath = false`、`setFlakeRegistry = false`，
> 所以必须用 `--flake <路径>` 的形式，不能省略。

## 日常更新

```Shell
sudo nixos-rebuild switch --flake ~/nixos-for-nabu#nabu
```

这一步会：

1. 构建新的系统 closure（toplevel）；
2. 通过 `boot.loader.external.installHook` 自动重建 UKI 并写入
   `/boot/efi/EFI/nixos/nabu.efi`（固定文件名，rEFInd 菜单无需改动）；
3. 切换运行中的系统到新 generation。

重启后即进入新系统。

## 回退（rollback）

### 用户态回退（最常见）

UKI 的 cmdline 使用稳定路径 `init=/nix/var/nix/profiles/system/init`，
因此**用户态回退只需改 profile 指向，UKI 不用动**：

```Shell
sudo nixos-rebuild switch --rollback --flake ~/nixos-for-nabu#nabu
# 或
sudo nix-env --rollback -p /nix/var/nix/profiles/system
```

重启即回到上一个 generation。

### 内核回退（新内核 boot 失败）

每次部署新 UKI 前，installHook 会把旧 UKI 保留为
`/boot/efi/EFI/nixos/nabu-previous.efi`。如果新内核启动失败：

1. 重启进入 rEFInd 菜单；
2. 选择除 `NixOS (nabu)` 之外的另一个 NixOS 项（rEFInd 自动扫描会
   列出 `nabu-previous.efi`，旧内核）；
3. 旧内核启动后，在系统里修复配置或执行 `--rollback`。

> 提示：若想要一个长期固定的兜底项，可手动
> `cp /boot/efi/EFI/nixos/nabu.efi /boot/efi/EFI/nixos/nabu-rescue.efi`，
> installHook 只管理 `nabu.efi` 与 `nabu-previous.efi`，不会动它。

## 性能提示

骁龙 855 上全量编译系统很慢，建议配置二进制缓存（Cachix / 自建
`nix-serve`），让设备端 rebuild 主要走下载而非本地编译。首次在设备上
rebuild 前，可先在 PC 上 `nix build .#nabu-rootfs .#nabu-esp` 预热缓存。

## 查看当前 UKI 的 cmdline

```Shell
nix shell nixpkgs#systemdUkify -c ukify inspect /boot/efi/EFI/nixos/nabu.efi | sed -n '/\.cmdline:/,/sha256/p'
```

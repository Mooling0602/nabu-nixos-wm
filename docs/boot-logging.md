# 启动日志排查

日志参数集中在 `nixos/boot.nix`；面板、背光及存储驱动的 initrd 加载顺序在
`nixos/hardware-nabu.nix`。当前启用详细启动日志，关闭 Plymouth 启动画面。

## 能看到哪些阶段

- EFI stub：`efi=debug` 请求固件控制台输出加载阶段的调试信息，能否显示取决于 UEFI 实现。
- Linux 内核：日志级别统一设为 8，启用时间戳、初始化函数跟踪和 4 MiB 日志缓冲区。
- initrd：主动加载背光和面板驱动；framebuffer 可用后，fbcon 立即接管并显示文字。
  systemd 管理器输出详细日志，服务的标准输出和错误同时进入控制台及 journal。
- 正常系统：显示 systemd 启动状态，管理器调试日志写入内核日志通道并由 journald 收集。
  登录界面启动后仍可通过 journal 查看日志。

小米平板 5 当前设备树没有提供 simple-framebuffer。Linux 接管后，屏幕必须等待
MSM DRM、面板和背光初始化，单靠日志参数无法保证从第一条内核指令起就有画面。
屏幕点亮前的消息会写入内核缓冲区，但过量日志仍可能覆盖旧记录。
要实时观察显示驱动初始化前的卡死，需要确认可用的硬件串口与 earlycon 配置；
这里不预设未知的 UART 地址，也不启用未经验证的 `earlycon=efifb`。

## 应用配置

在平板的仓库目录运行：

```sh
sudo nixos-rebuild boot --flake .#nabu
sudo reboot
```

这些修改需要重新生成 initrd 和引导参数，重启后生效。
`switch` 也能更新下次启动配置，但不能改变当前运行内核的启动参数。

## 查看和导出

```sh
cat /proc/cmdline
sudo journalctl --list-boots
sudo journalctl -b -k -o short-monotonic
sudo journalctl -b -o short-monotonic
sudo journalctl -b -1 -k -o short-monotonic
sudo journalctl -b -1 -o short-monotonic
sudo journalctl -b -o short-monotonic --no-pager > boot-current.log
sudo journalctl -b -1 -o short-monotonic --no-pager > boot-previous.log
```

`/proc/cmdline` 应只有一个 `loglevel=8`，不含 `quiet` 或 `splash`。
查看 initrd 的切根过程和模块加载：

```sh
sudo journalctl -b -u initrd-switch-root.service -u systemd-modules-load.service
sudo journalctl -b -k --no-pager | grep -Ei 'fbcon|drm|novatek|ktz8866|ath10k'
```

journal 持久存储上限设为 256 MiB，正常写盘同步间隔为 30 秒。
在根文件系统可写并完成日志落盘之前发生的死机、突然断电，以及缓冲区已覆盖的消息，
不保证能通过 `journalctl -b -1` 找回。

## 临时减少日志

详细日志会增加启动输出量，也可能影响时序。排查完成后，可以从 `boot.nix` 移除
`initcall_debug`、`ignore_loglevel`、`efi=debug`，将 `boot.consoleLogLevel` 降为 7，
并将 `systemd.log_level=debug` 改为 `systemd.log_level=info`。
仅临时降低当前 systemd 管理器日志级别可运行 `sudo systemd-analyze log-level info`。

参考：[内核启动参数](https://docs.kernel.org/admin-guide/kernel-parameters.html)、
[fbcon 接管行为](https://docs.kernel.org/fb/fbcon.html)、
[systemd 261 启动参数说明](https://github.com/systemd/systemd/blob/v261/man/systemd.xml)。

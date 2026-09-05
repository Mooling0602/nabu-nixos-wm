# niri 桌面配置 — 复刻 Fedora for nabu 的 nabu-fedora-configs-niri。
#
# Fedora 那边的技术栈：
#   greetd + dms-greeter --command niri  （Dank Linux 的登录界面）
#   niri 合成器 + DankMaterialShell 状态栏
#   pipewire/wireplumber 音频、fcitx5 输入法
#   fuzzel 启动器/电源菜单、swaylock-effects 锁屏、wvkbd 触屏键盘
# 这些在 nixpkgs 里都有对应模块/包，因此可以 1:1 复刻。
{
  pkgs,
  lib,
  ...
}:

let
  # 电源菜单（移植自 Fedora scripts/niri/fuzzel-pw-menu.sh）
  fuzzelPwMenu = pkgs.writeShellScriptBin "fuzzel-pw-menu" ''
    choice=$(printf "Logout\nReboot\nShutdown\nLockdown" | ${pkgs.fuzzel}/bin/fuzzel -w 10 -di)
    case "$choice" in
      Logout) ${pkgs.niri}/bin/niri msg action quit ;;
      Reboot) ${pkgs.systemd}/bin/reboot ;;
      Shutdown) ${pkgs.systemd}/bin/poweroff ;;
      Lockdown) ${pkgs.swaylock-effects}/bin/swaylock ;;
    esac
  '';

  # 屏幕旋转（移植自 Fedora scripts/niri/niri-rotate-display.sh）
  niriRotateDisplay = pkgs.writeShellScriptBin "niri-rotate-display" ''
    transform=$(${pkgs.niri}/bin/niri msg outputs | ${pkgs.gnugrep}/bin/grep Transform)
    rotation=$(echo "$transform" | ${pkgs.coreutils}/bin/cut -d ' ' -f 2)
    if [[ $rotation == "normal" ]]; then
      ${pkgs.niri}/bin/niri msg output DSI-1 transform 90
    elif [[ $rotation == "90°" ]]; then
      ${pkgs.niri}/bin/niri msg output DSI-1 transform 180
    elif [[ $rotation == "180°" ]]; then
      ${pkgs.niri}/bin/niri msg output DSI-1 transform 270
    elif [[ $rotation == "270°" ]]; then
      ${pkgs.niri}/bin/niri msg output DSI-1 transform normal
    else
      ${pkgs.niri}/bin/niri msg output DSI-1 transform normal
    fi
  '';

  # 触屏虚拟键盘切换（移植自 Fedora scripts/niri/wvkbd-toggle.sh）
  wvkbdToggle = pkgs.writeShellScriptBin "wvkbd-toggle" ''
    WVKBD_EXEC="wvkbd-mobintl"
    if ${pkgs.procps}/bin/pgrep -x "$WVKBD_EXEC" > /dev/null; then
      ${pkgs.procps}/bin/pkill -x "$WVKBD_EXEC"
    else
      ${pkgs.wvkbd}/bin/wvkbd-mobintl &
    fi
  '';

  # niri 配置（KDL）。平板核心：DankMaterialShell 状态栏 + 触摸 + 外接键盘绑定。
  niriConfigKdl = pkgs.writeText "niri-config.kdl" ''
    // niri config for Xiaomi Pad 5 (nabu)
    // 复刻 Fedora for nabu：DankMaterialShell 状态栏 + fuzzel + wvkbd + 电源菜单

    input {
        keyboard {
            xkb {
                layout "us"
            }
        }
    }

    // 触摸屏保留 niri 默认手势（单指滚动、双指缩放等）

    // 开机自启 DankMaterialShell 状态栏
    spawn-at-startup "dms"

    binds {
        // 启动器
        Mod+D { spawn "fuzzel"; }

        // 触屏虚拟键盘
        Mod+Shift+K { spawn "wvkbd-toggle"; }

        // 电源菜单
        Mod+Shift+E { spawn "fuzzel-pw-menu"; }

        // 屏幕旋转
        Mod+R { spawn "niri-rotate-display"; }

        // 关窗 / 退出
        Mod+Q { close-window; }
        Mod+Shift+Q { quit; }

        // 截图
        Print { screenshot; }
        Mod+Print { screenshot-screen; }

        // 平板侧键：音量 / 亮度
        XF86AudioRaiseVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.05+"; }
        XF86AudioLowerVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.05-"; }
        XF86AudioMute { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
        XF86MonBrightnessUp { spawn "brightnessctl" "s" "5%+"; }
        XF86MonBrightnessDown { spawn "brightnessctl" "s" "5%-"; }
    }

    // 工作区 / 窗口基础操作（外接键盘）
    Mod+H { focus-column-left; }
    Mod+L { focus-column-right; }
    Mod+J { focus-window-down; }
    Mod+K { focus-window-up; }
    Mod+Comma { consume-window-into-column; }
    Mod+Period { expel-window-from-column; }
    Mod+Return { spawn "foot"; }
    Mod+B { toggle-window-floating; }
    Mod+V { toggle-column-tabbed; }
  '';
in
{
  # == 合成器 ================================================================
  programs.niri = {
    enable = true;
    # 平板不需要 GNOME 的 Nautilus 文件选择器
    useNautilus = false;
  };

  # == 状态栏（DankMaterialShell）============================================
  programs.dms-shell = {
    enable = true;
    # 由 niri 的 spawn-at-startup 启动；禁用 systemd 用户服务避免双实例，
    # 且不依赖 greetd 会话下是否存在 systemd user session。
    systemd.enable = false;
  };

  # == 登录界面（greetd + dms-greeter -> niri）===============================
  # 等价于 Fedora 的 /etc/greetd/config.toml:
  #   [default_session] command = "dms-greeter --command niri"
  services.displayManager.dms-greeter = {
    enable = true;
    compositor.name = "niri";
  };

  # == 音频（pipewire + wireplumber，替代 pulseaudio）=======================
  services.pipewire = {
    enable = true;
    audio.enable = true;
    pulse.enable = true; # pipewire-pulse，等价 Fedora 的 pipewire-pulseaudio
  };

  # == 中文输入法（fcitx5）====================================================
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      qt6Packages.fcitx5-chinese-addons
      fcitx5-gtk
    ];
  };

  # == 字体（中文 + emoji，桌面必需）========================================
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];

  # == 桌面工具 ==============================================================
  environment.systemPackages = with pkgs; [
    fuzzel
    swaylock-effects
    wvkbd
    fastfetch
    brightnessctl
    foot # niri 默认终端
    fuzzelPwMenu
    niriRotateDisplay
    wvkbdToggle
  ];

  # 部署 niri 配置到 nabu 用户（首次创建，之后不覆盖用户的自定义）
  system.activationScripts.niriConfig = lib.stringAfter [ "users" ] ''
    if [ ! -e /home/nabu/.config/niri/config.kdl ]; then
      mkdir -p /home/nabu/.config/niri
      install -m 644 -o nabu -g users ${niriConfigKdl} /home/nabu/.config/niri/config.kdl
    fi
  '';
}

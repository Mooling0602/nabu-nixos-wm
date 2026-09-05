# niri + noctalia 桌面配置。
#
# noctalia（Wayland 桌面 shell）提供 bar / launcher / 控制中心 / 锁屏，
# 替代之前的 DankMaterialShell + fuzzel + swaylock 组合。
#
# 登录走 noctalia-greeter（greetd greeter），登录后 greetd 启动 niri 的
# niri-session（systemd user session）——spawn 动作因此拥有完整 PATH，
# 这是快捷键能否工作的关键。
{
  pkgs,
  ...
}:

let
  # 触屏虚拟键盘切换（平板输入所需）
  wvkbdToggle = pkgs.writeShellScriptBin "wvkbd-toggle" ''
    WVKBD_EXEC="wvkbd-mobintl"
    if ${pkgs.procps}/bin/pgrep -x "$WVKBD_EXEC" > /dev/null; then
      ${pkgs.procps}/bin/pkill -x "$WVKBD_EXEC"
    else
      ${pkgs.wvkbd}/bin/wvkbd-mobintl &
    fi
  '';

  # niri 配置（KDL）。采用 noctalia 官方 niri 集成 + 少量平板必要绑定。
  niriConfigKdl = pkgs.writeText "niri-config.kdl" ''
    // niri + noctalia（官方集成：docs.noctalia.dev/noctalia/compositor-settings/niri）

    input {
        keyboard {
            xkb {
                layout "us"
            }
        }

        // 平板电源键：不挂起、不关机
        disable-power-key-handling
    }

    // 开机自启 noctalia（bar + launcher + 控制中心 + 锁屏）
    spawn-at-startup "noctalia"

    // 现代圆角 + 按几何裁剪
    window-rule {
        geometry-corner-radius 20
        clip-to-geometry true
    }

    // noctalia 设置窗口浮动
    window-rule {
        match app-id="dev.noctalia.Noctalia"
        open-floating true
        default-column-width { fixed 1080; }
        default-window-height { fixed 920; }
    }

    // 允许 noctalia 的通知动作与窗口激活
    debug {
        honor-xdg-activation-with-invalid-serial
    }

    binds {
        // noctalia 核心面板
        Mod+Space { spawn-sh "noctalia msg panel-toggle launcher"; }
        Mod+S { spawn-sh "noctalia msg panel-toggle control-center"; }
        Mod+Comma { spawn-sh "noctalia msg settings-toggle"; }
        Alt+Tab { spawn-sh "noctalia msg window-switcher"; }

        // 音频 & 亮度（交由 noctalia 处理）
        XF86AudioRaiseVolume { spawn-sh "noctalia msg volume-up"; }
        XF86AudioLowerVolume { spawn-sh "noctalia msg volume-down"; }
        XF86AudioMute { spawn-sh "noctalia msg volume-mute"; }
        XF86MonBrightnessUp { spawn-sh "noctalia msg brightness-up"; }
        XF86MonBrightnessDown { spawn-sh "noctalia msg brightness-down"; }

        // 终端
        Mod+Return { spawn "foot"; }

        // 触屏虚拟键盘切换
        Mod+Shift+K { spawn "wvkbd-toggle"; }

        // 关窗 / 退出
        Mod+Q { close-window; }
        Mod+Shift+Q { quit; }
    }
  '';
in
{
  # == 合成器 ================================================================
  programs.niri = {
    enable = true;
    useNautilus = false;
  };

  # == 桌面 shell（noctalia，替代 DankMaterialShell）=========================
  programs.noctalia = {
    enable = true;
    # NetworkManager / bluetooth / UPower / power-profiles-daemon
    recommendedServices.enable = true;
  };

  # == 登录界面（noctalia-greeter -> greetd -> niri-session）=================
  services.displayManager.noctalia-greeter = {
    enable = true;
    settings = {
      session.default = "niri";
      user.default = "nabu";
      idle.timeout = 0; # 登录界面不熄屏
      keyboard.layout = "us";
    };
  };

  # == 音频（pipewire + wireplumber）========================================
  services.pipewire = {
    enable = true;
    audio.enable = true;
    pulse.enable = true;
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

  # == 字体 ==================================================================
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];

  # == 桌面工具 ==============================================================
  environment.systemPackages = with pkgs; [
    foot # 终端
    wvkbd # 触屏虚拟键盘
    wvkbdToggle
  ];

  # niri 系统级配置（声明式）。niri 会优先读取 ~/.config/niri/config.kdl，
  # 若不存在则回退到 /etc/niri/config.kdl，用户可在 home 下自行覆盖。
  environment.etc."niri/config.kdl".source = niriConfigKdl;
}

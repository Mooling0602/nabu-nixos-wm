# Daily desktop and mobile applications.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    kitty
    alacritty
    zellij
    fastfetch
    qq
    wechat
    telegram-desktop
    # zed # not friendly for touchscreen users
    google-chrome
    vscode
    gh
    # Codex Desktop (github:ilysenko/codex-desktop-linux, via overlay in flake.nix)
    codex-desktop
    codex-cli
    kdePackages.ksshaskpass
    kdePackages.dolphin
    kdePackages.kate
    kdePackages.kdeconnect-kde
  ];

  # Run the Electron-based Codex desktop on its native Wayland backend instead
  # of XWayland (better HiDPI/touch behaviour on niri).  The package wrapper
  # only applies its own x11 default when this variable is unset, so a
  # per-launch override (e.g. CODEX_OZONE_PLATFORM=x11) still works.
  home.sessionVariables.CODEX_OZONE_PLATFORM = "wayland";

  programs.vscode.enable = true;
}

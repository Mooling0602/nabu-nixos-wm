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

  # Codex Desktop is pinned to its native Wayland backend by patching the
  # package's desktop entry in flake.nix (overlay); terminal launches can pass
  # --ozone-platform=wayland explicitly.

  programs.vscode.enable = true;
}

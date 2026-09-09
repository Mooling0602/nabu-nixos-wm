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
    kdePackages.ksshaskpass
    kdePackages.dolphin
    kdePackages.kate
    kdePackages.kdeconnect-kde
  ];

  programs.vscode.enable = true;
}

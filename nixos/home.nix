{ pkgs, ... }:

{
  programs.vscode.enable = true;
  home.packages = with pkgs; [
    zellij
    fastfetch
    qq
    wechat
    telegram-desktop
    # zed # not friendly for touchscreen users
    vscode
    gh
    kdePackages.ksshaskpass
  ];
}

{ pkgs, inputs, ... }:

{
  imports = [
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];
  services.flatpak.enable = true;
  services.flatpak.packages = [
    "cn.wps.wps_365"
  ];
  programs.vscode.enable = true;
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  home.stateVersion = "26.11";
  home.packages = with pkgs; [
    # fonts
    sarasa-gothic
    noto-fonts-cjk-serif
    maple-mono.NF-CN

    # icon theme
    tela-icon-theme

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
    kdePackages.ksshaskpass
    kdePackages.dolphin
    kdePackages.kate
    kdePackages.kdeconnect-kde
  ];

  programs.kitty = {
    enable = true;
    font = {
      name = "Maple Mono NF CN";
      size = 12;
    };
    settings = {
      background_opacity = 0.6;
      background_blur = 64;
      hide_window_decorations = "yes";
      confirm_os_window_close = 0;
    };
  };

  xresources.properties = {
    "Xcursor.size" = 48;
    "Xft.dpi" = 192;
  };
}

{ pkgs, inputs, ... }:

{
  imports = [
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];
  services.flatpak.enable = true;
  services.flatpak.packages = [];
  programs.vscode.enable = true;
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  home.stateVersion = "26.11";
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

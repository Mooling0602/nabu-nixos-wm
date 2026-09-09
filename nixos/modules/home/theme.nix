# Icon theme and HiDPI (192 dpi panel) cursor/scaling settings.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    tela-icon-theme
  ];

  xresources.properties = {
    "Xcursor.size" = 48;
    "Xft.dpi" = 192;
  };
}

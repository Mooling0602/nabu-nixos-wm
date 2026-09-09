# Terminal emulator configuration (kitty, HiDPI + translucency).
{ ... }:

{
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
}

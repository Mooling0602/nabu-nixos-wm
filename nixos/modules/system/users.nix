# User account and console autologin.
{
  users.users.nabu = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      # TouchpadEmulator reads /dev/input/* and writes /dev/uinput
      "input"
    ];
    initialPassword = "nabu";
  };

  # greetd + noctalia-greeter (见 desktop.nix) 接管图形登录，TTY 自动登录仍保留。
  services.getty.autologinUser = "nabu";
}

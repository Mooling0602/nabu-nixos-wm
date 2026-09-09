# Core system settings: identity, Nix, locale, console, power behaviour.
{
  pkgs,
  ...
}:

{
  # == Identity ===============================================================
  networking.hostName = "nabu";
  system.stateVersion = "25.11";

  # == Nix ====================================================================
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;

  # This is a bring-up image, and cross-building the NixOS manuals pulls in a
  # browser and a large documentation toolchain that is irrelevant at boot.
  documentation.enable = false;
  documentation.nixos.enable = false;

  # The desktop module (desktop.nix) configures fcitx5 and desktop fonts.

  # == Console font (TTY) ==============================
  console = {
    earlySetup = true;
    font = "ter-132n";
    packages = [ pkgs.terminus_font ];
  };

  # == Power ==================================================================
  # Tablet power key: neither suspend nor power off. Screen on/off is left to
  # the compositor (niri) and the kernel, avoiding suspend on nabu causing a
  # brief "lights on then off" glitch.
  services.logind.settings.Login.HandlePowerKey = "ignore";

  # The system is stateless enough for this; speeds up shutdown
  systemd.settings.Manager.DefaultTimeoutStopSec = "10s";
}

# System packages and device-specific package overrides.
#
# The overrides below exist purely to keep the cross-compiled bring-up image
# small and buildable; drop them once nixpkgs fixes the underlying issues.
{
  lib,
  pkgs,
  ...
}:

let
  # Upstream alsa-utils enables the audio loopback tester (alsabat) and a
  # PipeWire plugin directory by default.  For a recovery/bring-up image that
  # pulls FFTW (and therefore a complete target gfortran compiler) plus much of
  # the desktop audio stack into an otherwise minimal cross build.  Keep the
  # normal mixer/playback/UCM tools, but omit those optional test/plugin bits.
  alsaUtilsMinimal = (pkgs.alsa-utils.override { withPipewireLib = false; }).overrideAttrs (old: {
    configureFlags = (old.configureFlags or [ ]) ++ [ "--disable-bat" ];
    buildInputs = lib.remove pkgs.fftwFloat (old.buildInputs or [ ]);
    # The upstream postFixup also wraps every utility with alsa-plugins.  That
    # plugin bundle brings an entire desktop multimedia closure (PulseAudio,
    # JACK, FFmpeg/GStreamer and another FFTW) into this console image.  Direct
    # ALSA hardware access and UCM only need alsa-lib; a later desktop/PipeWire
    # configuration will supply its own plugin path.
    postFixup = ''
      mv $out/bin/alsa-info.sh $out/bin/alsa-info
      wrapProgram $out/bin/alsa-info \
        --prefix PATH : "${lib.makeBinPath [
          pkgs.which
          pkgs.pciutils
          pkgs.procps
          pkgs.tree
        ]}" \
        --prefix PATH : $out/bin
    '';
  });
in
{
  environment.systemPackages = with pkgs; [
    vim
    nano
    git
    wget
    curl
    perl
    python3
    usbutils
    alsaUtilsMinimal
    firefox
    kitty
    brightnessctl
    nil
    nixd
    direnv
    clash-verge-rev
    mission-center
    touchpad-emulator
  ];

  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # Enable flatpak service so nix-flatpak can call it
  services.flatpak.enable = true;

  # == TouchpadEmulator ========================================================
  # Touchscreen-as-touchpad emulator (pkgs.touchpad-emulator).  nabu's input
  # devices (touchscreen "NVTCapacitiveTouchScreen", buttons "gpio-keys" and
  # "pm8941_resin") match the program's built-in device table, so it works
  # without patches.  It needs: the uinput module for the virtual mouse
  # device, permission for the `input` group on /dev/uinput (upstream's
  # LaunchTouchpadEmulator.sh instead uses a pkexec chmod hack), and the user
  # in `input` (see users.nix).  Volume keys still reach the desktop because
  # the program forwards quick taps as volume events.
  boot.kernelModules = [ "uinput" ];
  services.udev.extraRules = ''
    # TouchpadEmulator: allow the `input` group to create the virtual mouse
    # device.  Mirrors upstream's 10-uinput.rules.
    KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0660", GROUP="input"
  '';
}

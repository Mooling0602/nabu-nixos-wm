# Minimal NixOS configuration for Xiaomi Pad 5 (nabu).
# Desktop environment, input methods, fonts etc. are intentionally left out —
# configure them yourself on the running system.
{
  pkgs,
  lib,
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

  # nabu is Wi-Fi-only.  The stock NetworkManager derivation nevertheless
  # enables ModemManager and carries BlueZ even though its BlueZ DUN feature is
  # disabled.  While cross-compiling it also builds a second native
  # NetworkManager merely to copy documentation into the target outputs; that
  # currently trips a nixpkgs dbus-python cross-package bug.  Keep the actual
  # NetworkManager/iwd Wi-Fi path while dropping these unused inputs.
  networkManagerNabu = pkgs.networkmanager.overrideAttrs (old: {
    mesonFlags = map (
      flag: if lib.hasPrefix "-Dmodem_manager=" flag then "-Dmodem_manager=false" else flag
    ) (old.mesonFlags or [ ]);
    buildInputs = lib.subtractLists [
      pkgs.bluez5
      pkgs.modemmanager
    ] (old.buildInputs or [ ]);
    postFixup = ''
      mkdir -p "$man" "$devdoc"
      # This newly installed generator keeps /bin/bash in the upstream cross
      # build. NixOS only provides /bin/sh. Generators also need explicit tool
      # paths because they run before the normal service environment exists.
      substituteInPlace "$out/lib/systemd/system-generators/nm-initrd-generator.sh" \
        --replace-fail '#!/bin/bash' '#!${pkgs.bash}/bin/bash' \
        --replace-fail 'ln -s ' '${pkgs.coreutils}/bin/ln -s ' \
        --replace-fail 'mkdir -p ' '${pkgs.coreutils}/bin/mkdir -p ' \
        --replace-fail '/usr/lib/systemd/system/' "$out/lib/systemd/system/"
    '';
  });
in
{
  imports = [
    ./hardware-nabu.nix
    ./uki.nix
    ./rootfs-image.nix
  ];

  # == Identity ===============================================================
  networking.hostName = "nabu";
  system.stateVersion = "25.11";

  # == Users ==================================================================
  users.users.nabu = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "input"
    ];
    initialPassword = "nabu";
  };

  # Minimal image (no DE): drop straight into a tty as $USER automatically.
  services.getty.autologinUser = "nabu";

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

  # == Locale =================================================================
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "zh_CN.UTF-8";
    LC_IDENTIFICATION = "zh_CN.UTF-8";
    LC_MEASUREMENT = "zh_CN.UTF-8";
    LC_MONETARY = "zh_CN.UTF-8";
    LC_NUMERIC = "zh_CN.UTF-8";
    LC_PAPER = "zh_CN.UTF-8";
    LC_TELEPHONE = "zh_CN.UTF-8";
    LC_TIME = "zh_CN.UTF-8";
  };
  # Note: no i18n.inputMethod here — add fcitx5 + addons yourself later.

  # == Console font (TTY only; no desktop fonts) ==============================
  console = {
    earlySetup = true;
    font = "ter-132n";
    packages = [ pkgs.terminus_font ];
  };

  # == Minimal essentials ======================================================
  environment.systemPackages = with pkgs; [
    vim
    nano
    git
    usbutils
    alsaUtilsMinimal
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true; # initial setup convenience
    };
  };

  networking.networkmanager.package = networkManagerNabu;
  networking.modemmanager.enable = false;

  # Produce an uncompressed raw ext4 .img — directly flashable via
  # `fastboot flash linux nabu-rootfs.ext4.img`
  nabu.image.compress = false;

  # Tablet-friendly: power button suspends
  services.logind.settings.Login.HandlePowerKey = "suspend";

  # The system is stateless enough for this; speeds up shutdown
  systemd.settings.Manager.DefaultTimeoutStopSec = "10s";
}

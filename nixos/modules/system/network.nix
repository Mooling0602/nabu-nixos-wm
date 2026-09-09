# Network stack: NetworkManager + iwd, with nabu-specific package overrides.
{
  lib,
  pkgs,
  ...
}:

let
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
      # In the cross build this generator keeps a raw #!/bin/bash (patchShebangs
      # skips it); in native builds patchShebangs has already rewritten it to
      # the store bash.  Replace the shebang non-fatally, but require the tool
      # paths below (generators run before the normal service environment).
      substituteInPlace "$out/lib/systemd/system-generators/nm-initrd-generator.sh" \
        --replace '#!/bin/bash' '#!${pkgs.bash}/bin/bash' \
        --replace-fail 'ln -s ' '${pkgs.coreutils}/bin/ln -s ' \
        --replace-fail 'mkdir -p ' '${pkgs.coreutils}/bin/mkdir -p ' \
        --replace-fail '/usr/lib/systemd/system/' "$out/lib/systemd/system/"
    '';
  });
in
{
  networking.networkmanager = {
    package = networkManagerNabu;
    enable = true;
    wifi.backend = "iwd";
  };
  networking.wireless.enable = false; # avoid wpa_supplicant conflict
  networking.modemmanager.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true; # initial setup convenience
    };
  };

  programs.clash-verge = {
    enable = true;
    serviceMode = true;
    tunMode = true;
  };
}

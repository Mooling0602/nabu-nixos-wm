# Custom package set for nixos-for-nabu.
# Exposed as an overlay so `pkgs.kernel-sm8150` etc. work inside the
# NixOS configuration.
final: prev: {
  # Mainline sm8150 kernel (6.17) with nabu support
  kernel-sm8150 = final.callPackage ./kernel { };

  # Qualcomm protection domain mapper (missing from nixpkgs)
  pd-mapper = final.callPackage ./pd-mapper.nix { };

  # Device firmware from the postmarketOS firmware repo
  xiaomi-nabu-firmware = final.callPackage ./nabu-firmware.nix { };

  # ALSA UCM profile for sm8150-nabu audio.  ALSA only searches the
  # alsa-ucm-conf datadir (share/alsa/ucm2) — never /etc — so the profile is
  # merged into alsa-ucm-conf below.  The conf.d directory must be the card's
  # driver name "snd_soc_sm8150": ucm.conf probes conf.d/${CardDriver}/.
  nabu-alsa-ucm = final.stdenv.mkDerivation {
    pname = "nabu-alsa-ucm";
    version = "1";
    src = ./alsa-ucm;
    installPhase = ''
      mkdir -p "$out/share/alsa/ucm2/conf.d/snd_soc_sm8150" \
               "$out/share/alsa/ucm2/Xiaomi/nabu"
      install -Dm644 sm8150.conf \
        "$out/share/alsa/ucm2/conf.d/snd_soc_sm8150/snd_soc_sm8150.conf"
      install -Dm644 HiFi.conf \
        "$out/share/alsa/ucm2/Xiaomi/nabu/HiFi.conf"
    '';
    meta = {
      description = "ALSA UCM profiles for Xiaomi Pad 5 (nabu)";
      platforms = final.lib.platforms.linux;
    };
  };

  # Merge the nabu profile into alsa-ucm-conf so alsa-lib (and WirePlumber)
  # discover it from the datadir, where ALSA actually looks.
  alsa-ucm-conf = final.symlinkJoin {
    name = "alsa-ucm-conf";
    paths = [
      prev.alsa-ucm-conf
      final.nabu-alsa-ucm
    ];
  };
}

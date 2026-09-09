{
  description = "NixOS WM configuration for Xiaomi Pad 5 (nabu)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    xwayland-satellite = {
      url = "git+https://github.com/Mooling0602/xwayland-satellite";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Codex Desktop; consumes the upstream flake's own pinned nixpkgs so the
    # Rust/Electron build stays on the toolchain the project tests against.
    codex-desktop-linux.url = "github:ilysenko/codex-desktop-linux";
    nix-flatpak.url = "github:gmodena/nix-flatpak";
  };

  outputs =
    inputs@{ self, nixpkgs, home-manager, nix-flatpak, xwayland-satellite
    , codex-desktop-linux, ... }:
    let
      lib = nixpkgs.lib;

      sharedModules = [
        {
          nixpkgs.overlays = [
            (import ./pkgs)
            # Expose the user's fork of xwayland-satellite as pkgs.xwayland-satellite,
            # overriding the nixpkgs one.  Mirrors dms-starter's flake.nix.
            (
              final: prev:
              {
                xwayland-satellite =
                  xwayland-satellite.packages.${final.stdenv.hostPlatform.system}.xwayland-satellite;
                codex-desktop =
                  codex-desktop-linux.packages.${final.stdenv.hostPlatform.system}.codex-desktop;
              }
            )
          ];
        }
        home-manager.nixosModules.home-manager
        nix-flatpak.nixosModules.nix-flatpak
        ./nixos/configuration.nix
      ];

      # ESP packaging lives in nixos/modules/build/esp-image.nix and is
      # exposed as system.build.esp-image on the evaluated configuration.

    in
    {
      # Native aarch64 configuration (build on the device / aarch64 builders)
      nixosConfigurations.nabu = lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = sharedModules;
      };

      packages =
        let
          # Cross-evaluated NixOS config: buildPlatform = current system,
          # hostPlatform = aarch64 (from hardware-nabu.nix).
          crossConfigFor =
            system:
            lib.nixosSystem {
              # configuration.nix and modules/home consume `inputs`; without
              # specialArgs the cross evaluation fails with
              # "attribute 'inputs' missing" (native eval already had this).
              specialArgs = { inherit inputs; };
              modules =
                [
                  {
                    nixpkgs.buildPlatform.system = system;
                  }
                ]
                ++ sharedModules;
            };
        in
        lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
          system:
          let
            cfg =
              if system == "aarch64-linux" then
                self.nixosConfigurations.nabu.config
              else
                (crossConfigFor system).config;
          in
          {
            # Bootable ESP image: systemd-boot + kernel + initrd + DTB + Android.
            nabu-esp = cfg.system.build.esp-image;
            # kernel alone (use .configfile passthru to inspect the config)
            nabu-kernel = cfg.system.build.kernel;
            # Flashable ext4 image from the same cross-evaluated configuration
            # as the ESP, so both artifacts reference the same system closure.
            nabu-rootfs = cfg.system.build.rootfs-image;
            default = self.packages.${system}.nabu-esp;
          }
        );
    };
}

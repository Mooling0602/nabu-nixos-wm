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
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    impermanence.url = "github:nix-community/impermanence";
    # The impermanence flake's home-manager input is unused here (the NixOS
    # module is what gets imported); follow our own to avoid a second copy.
    impermanence.inputs.nixpkgs.follows = "nixpkgs";
    impermanence.inputs.home-manager.follows = "home-manager";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      nix-flatpak,
      xwayland-satellite,
      impermanence,
      ...
    }:
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
              }
            )
          ];
        }
        home-manager.nixosModules.home-manager
        nix-flatpak.nixosModules.nix-flatpak
      ];

      # nixosConfigurations key for each storage variant.
      configName = variant: "${variant}-nabu";
      # Host name baked into each system.  `nixos-rebuild switch --flake .`
      # (without an explicit #hostname) resolves the current host name to
      # nixosConfigurations.<host name>, so each variant's host name must be a
      # key or alias that points at its own configuration:
      #   ext4        -> "nabu"              (alias of ext4-nabu, keeps the old name)
      #   impermanent -> "impermanent-nabu"
      # Without this the impermanent system resolved to the ext4 config and
      # rebuilt the wrong root filesystem (ending in emergency mode).
      hostNameFor = variant: if variant == "ext4" then "nabu" else configName variant;
      variants = {
        ext4 = ./nixos/storage/ext4.nix;
        impermanent = ./nixos/storage/impermanent.nix;
      };
      mkSystem =
        variant: buildSystem:
        lib.nixosSystem {
          # nixos/configuration.nix and nixos/home.nix consume `inputs`; without
          # specialArgs the evaluation fails with "attribute 'inputs' missing".
          specialArgs = { inherit inputs; };
          modules =
            sharedModules
            ++ [
              { networking.hostName = hostNameFor variant; }
              ./nixos/configuration.nix
              variants.${variant}
            ]
            ++ lib.optional (variant == "impermanent") impermanence.nixosModules.impermanence
            ++ lib.optional (buildSystem != null) { nixpkgs.buildPlatform.system = buildSystem; };
        };
    in
    {
      checks = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system: {
        filesystem-images = import ./tests/filesystem-images.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit lib;
        };
        storage-boot = import ./tests/storage-boot.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit lib impermanence;
        };
      });

      nixosConfigurations =
        lib.mapAttrs' (variant: _: {
          name = configName variant;
          value = mkSystem variant null;
        }) variants
        // {
          nabu = self.nixosConfigurations.ext4-nabu;
        };

      packages = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
        system:
        let
          configs = lib.mapAttrs (
            variant: _:
            if system == "aarch64-linux" then
              self.nixosConfigurations."${variant}-nabu".config
            else
              (mkSystem variant system).config
          ) variants;
          images = lib.concatMapAttrs (variant: config: {
            "${variant}-nabu-esp" = config.system.build.esp-image;
            "${variant}-nabu-rootfs" = config.system.build.rootfs-image;
          }) configs;
        in
        images
        // {
          # Preserve the original ext4 entry points. Each pair uses one evaluation.
          nabu-esp = images.ext4-nabu-esp;
          nabu-rootfs = images.ext4-nabu-rootfs;
          nabu-kernel = configs.ext4.system.build.kernel;
          default = images.ext4-nabu-esp;
        }
      );
    };
}

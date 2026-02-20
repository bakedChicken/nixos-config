{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia-flake = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./users
        ./gui
      ];

      debug = true;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        { pkgs, ... }:
        {
          formatter = pkgs.nixfmt-tree;

          devShells.default = pkgs.mkShell {
            env = {
              ZED_ALLOW_EMULATED_GPU = 1;
            };

            packages = with pkgs; [
              nixfmt-tree
              nixd
              nil
            ];
          };
        };

      flake = {
        nixosModules = {
          home-manager = {
            imports = [
              inputs.home-manager.nixosModules.home-manager
            ];

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
          };

          nix-configuration = {
            nix = {
              settings = {
                experimental-features = [
                  "nix-command"
                  "flakes"
                ];
                trusted-users = [
                  "root"
                  "@wheel"
                ];
                substituters = [ "https://cache.nixos.org?priority=40" ];
                trusted-public-keys = [
                  "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
                ];
              };
              channel.enable = false;
            };
          };
        };

        nixosConfigurations = {
          nixos-development-environment = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit inputs; };
            modules = [
              inputs.self.nixosModules.nix-configuration
              inputs.self.nixosModules.home-manager
              inputs.self.nixosModules.artur
              inputs.self.nixosModules.sunshine
              inputs.self.nixosModules.xserver
              inputs.self.nixosModules.kde-desktop
              (
                { pkgs, ... }:
                {
                  boot.initrd.systemd.enable = true;
                  boot.initrd.availableKernelModules = [ "sd_mod" ];

                  boot.loader = {
                    systemd-boot = {
                      enable = true;
                      configurationLimit = 16;
                    };
                    efi.canTouchEfiVariables = true;
                    timeout = 3;
                  };

                  fileSystems."/" = {
                    device = "/dev/disk/by-uuid/948ba4c0-bac6-4171-82cd-7425841ef4a4";
                    fsType = "ext4";
                  };

                  fileSystems."/boot" = {
                    device = "/dev/disk/by-uuid/56F9-3FCF";
                    fsType = "vfat";
                    options = [
                      "fmask=0022"
                      "dmask=0022"
                    ];
                  };

                  swapDevices = [
                    { device = "/dev/disk/by-uuid/294971f2-ef20-4e70-8de0-2527f904b864"; }
                  ];

                  networking.hostName = "nixos-development-environment";
                  networking.useNetworkd = true;
                  systemd.network.enable = true;
                  virtualisation.hypervGuest.enable = true;

                  time.timeZone = "Europe/Vienna";
                  i18n.defaultLocale = "en_US.UTF-8";
                  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];

                  environment.systemPackages = with pkgs; [
                    git
                  ];

                  system.stateVersion = "25.11";
                }
              )
            ];
          };
        };
      };
    };
}

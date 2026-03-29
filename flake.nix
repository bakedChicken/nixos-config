{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    noctalia-flake = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      flake-parts,
      nixos-hardware,
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
            packages = with pkgs; [
              nixfmt-tree
              nixd
              nil
              nh
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

          nix-configuration =
            { pkgs, ... }:
            {
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
                optimise.automatic = true;
                gc.automatic = true;
              };

              environment.systemPackages = with pkgs; [
                gitMinimal
                neovim
                helix
              ];

              environment.variables = {
                EDITOR = "nvim";
                VISUAL = "nvim";
              };

              boot.loader.systemd-boot.enable = true;
              boot.initrd.systemd.enable = true;
              boot.kernelPackages = pkgs.linuxPackages_latest;

              time.timeZone = "Europe/Vienna";
              i18n.defaultLocale = "en_US.UTF-8";

              networking.networkmanager.enable = true;

              nixpkgs.config.allowUnfree = true;
              system.stateVersion = "25.11";
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
              inputs.self.nixosModules.nobile
              inputs.self.nixosModules.xserver
              inputs.self.nixosModules.kde-desktop
              {
                boot.initrd.availableKernelModules = [ "sd_mod" ];

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
                virtualisation.hypervGuest.enable = true;

                services.openssh.enable = true;
                networking.firewall.allowedTCPPorts = [ 22 ];

                services.pipewire.enable = false;
                services.pulseaudio.enable = true;
              }
            ];
          };
          nobile-development-environment = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit inputs; };
            modules = [
              nixos-hardware.nixosModules.framework-amd-ai-300-series
              inputs.self.nixosModules.nix-configuration
              inputs.self.nixosModules.home-manager
              inputs.self.nixosModules.nobile
              inputs.self.nixosModules.niri-wm
              {
                boot.initrd.availableKernelModules = [
                  "xhci_pci"
                  "nvme"
                  "thunderbolt"
                  "usbhid"
                  "usb_storage"
                  "sd_mod"
                ];
                boot.kernelModules = [ "kvm-amd" ];
                boot.supportedFilesystems = [ "ntfs" ];

                hardware.enableRedistributableFirmware = true;
                hardware.bluetooth.enable = true;
                hardware.graphics = {
                  enable = true;
                  enable32Bit = true;
                };
                services.hardware.bolt.enable = true;
                services.upower.enable = true;

                fileSystems."/" = {
                  device = "/dev/disk/by-uuid/7a6841ce-432c-4ea4-b9cb-65748577cbe3";
                  fsType = "ext4";
                };

                fileSystems."/boot" = {
                  device = "/dev/disk/by-uuid/DDC1-F689";
                  fsType = "vfat";
                  options = [
                    "fmask=0077"
                    "dmask=0077"
                  ];
                };

                networking.hostName = "nobile-development-environment";
              }
            ];
          };
        };
      };
    };
}

{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia-flake = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    k0s = {
      url = "github:vangourd/k0s-nix/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      disko,
      k0s,
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

          incus-container = { modulesPath, ... }: {
            imports = [
              "${modulesPath}/virtualisation/lxc-container.nix"
            ];
          };

          k0s-node-common = {
            services.k0s = {
              enable = true;
              role = "worker";
            };

            virtualisation.hypervGuest.enable = true;

            disko.devices = {
              disk = {
                main = {
                  device = "/dev/sda";
                  type = "disk";
                  content = {
                    type = "gpt";
                    partitions = {
                      ESP = {
                        priority = 1;
                        name = "ESP";
                        start = "1M";
                        end = "128M";
                        type = "EF00";
                        content = {
                          type = "filesystem";
                          format = "vfat";
                          mountpoint = "/boot";
                          mountOptions = [ "umask=0077" ];
                        };
                      };
                      root = {
                        size = "100%";
                        content = {
                          type = "btrfs";
                          extraArgs = [ "-f" ];
                          mountpoint = "/";
                          mountOptions = [
                            "compress=zstd"
                            "noatime"
                          ];
                        };
                      };
                    };
                  };
                };
              };
            };
          };
        };

        nixosConfigurations = {
          nixos-development-environment = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit inputs; };
            modules = [
              disko.nixosModules.default
              k0s.nixosModules.default
              self.nixosModules.nix-configuration
              self.nixosModules.home-manager
              self.nixosModules.artur
              self.nixosModules.nobile
              self.nixosModules.xserver
              self.nixosModules.kde-desktop
              {
                disko.devices.disk.main = {
                  type = "disk";
                  device = "/dev/sda";
                  content = {
                    type = "gpt";
                    partitions = {
                      ESP = {
                        priority = 1;
                        name = "ESP";
                        start = "1M";
                        end = "128M";
                        type = "EF00";
                        content = {
                          type = "filesystem";
                          format = "vfat";
                          mountpoint = "/boot";
                          mountOptions = [ "umask=0077" ];
                        };
                      };
                      root = {
                        size = "100%";
                        content = {
                          type = "btrfs";
                          extraArgs = [ "-f" ];
                          subvolumes = {
                            "/root" = {
                              mountpoint = "/";
                              mountOptions = [
                                "compress=zstd"
                                "noatime"
                              ];
                            };
                            "/home" = {
                              mountpoint = "/home";
                              mountOptions = [
                                "compress=zstd"
                                "noatime"
                              ];
                            };
                            "/nix" = {
                              mountpoint = "/nix";
                              mountOptions = [
                                "compress=zstd"
                                "noatime"
                              ];
                            };
                          };
                        };
                      };
                    };
                  };
                };

                networking.hostName = "nixos-development-environment";
                virtualisation.hypervGuest.enable = true;

                services.openssh.enable = true;
                networking.firewall.allowedTCPPorts = [ 22 ];

                services.pipewire.enable = false;
                services.pulseaudio.enable = true;

                home-manager.users.artur.imports = [
                  self.homeModules.artur
                ];
              }
            ];
          };
          nobile-development-environment = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit inputs; };
            modules = [
              inputs.self.nixosModules.nix-configuration
              inputs.self.nixosModules.home-manager
              inputs.self.nixosModules.nobile
              inputs.self.nixosModules.niri-wm
              {
                hardware.facter.reportPath = ./facter.json;
                services.hardware.bolt.enable = true;
                services.upower.enable = true;
                services.power-profiles-daemon.enable = true;

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
          k8s-master-node = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit inputs; };
            modules = [
              k0s.nixosModules.default
              self.nixosModules.incus-container
              self.nixosModules.nix-configuration
              self.nixosModules.artur
              {
                networking.hostName = "k8s-master-node";
                services.k0s = {
                  enable = true;
                  role = "controller";
                  controller.isLeader = true;
                };
              }
            ];
          };
          k8s-node-01 = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit inputs; };
            modules = [
              disko.nixosModules.disko
              k0s.nixosModules.default
              self.nixosModules.nix-configuration
              self.nixosModules.k8s-node-common
              self.nixosModules.artur
              {
                networking.hostName = "k8s-node-01";

                services.k0s = {
                  enable = true;
                  role = "controller";
                  isLeader = true;
                  apiAddress = "";
                };
              }
            ];
          };
        };
      };
    };
}

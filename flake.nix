{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      disko,
      deploy-rs,
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
        { pkgs, inputs', ... }:
        {
          formatter = pkgs.nixfmt-tree;

          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              nixfmt-tree
              nil
              inputs'.deploy-rs.packages.deploy-rs
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
            home-manager.sharedModules = [
              inputs.nvf.homeManagerModules.default
            ];
          };

          physical-host =
            { pkgs, ... }:
            {
              boot.loader.systemd-boot.enable = true;
              boot.initrd.systemd.enable = true;
              boot.kernelPackages = pkgs.linuxPackages_latest;
              networking.networkmanager.enable = true;
            };

          hyperv-vm = {
            virtualisation.hypervGuest.enable = true;
          };

          common-nix-module =
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
              ];

              environment.variables = {
                EDITOR = "nvim";
                VISUAL = "nvim";
              };

              services.avahi = {
                enable = true;
                nssmdns4 = true;
                nssmdns6 = true;
                publish = {
                  enable = true;
                  userServices = true;
                  domain = true;
                };
              };

              time.timeZone = "Europe/Vienna";
              i18n.defaultLocale = "en_US.UTF-8";

              nixpkgs.config.allowUnfree = true;
              system.stateVersion = "25.11";
            };

          k8s-node-common = {
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
              self.nixosModules.common-nix-module
              self.nixosModules.physical-host
              self.nixosModules.hyperv-vm
              self.nixosModules.home-manager
              self.nixosModules.artur
              self.nixosModules.xserver
              self.nixosModules.kde-desktop
              {
                networking.hostName = "nixos-development-environment";

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

                services.pipewire.enable = false;
                services.pulseaudio.enable = true;

                home-manager.users.artur.imports = [
                  self.homeModules.artur
                ];
              }
            ];
          };

          k8s-master-node = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit inputs; };
            modules = [
              disko.nixosModules.default
              self.nixosModules.common-nix-module
              self.nixosModules.k8s-node-common
              self.nixosModules.artur
              (
                { modulesPath, ... }:
                {
                  imports = [
                    "${modulesPath}/virtualisation/lxc-container.nix"
                  ];

                  networking.hostName = "k8s-master-node";
                }
              )
            ];
          };
        };

        deploy.nodes = {
          k8s-master-node = {
            hostname = "k8s-master-node.local";
            interactiveSudo = true;
            profiles.system = {
              user = "root";
              path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.k8s-master-node;
            };
          };
        };

        checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
      };
    };
}

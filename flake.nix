{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    umbriel.url = "git+https://github.com/noctalia-dev/umbriel";

    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix-rekey = {
      url = "github:oddlama/agenix-rekey";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      nvf,
      flake-parts,
      disko,
      agenix,
      agenix-rekey,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { withSystem, ... }:
      {
        imports = [
          home-manager.flakeModules.home-manager
          agenix-rekey.flakeModules.default
          disko.flakeModules.default
          ./users
          ./gui
          ./kubernetes
        ];

        debug = true;

        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];

        perSystem =
          {
            pkgs,
            inputs',
            config,
            ...
          }:
          {
            formatter = pkgs.nixfmt-tree;

            devShells.default = pkgs.mkShellNoCC {
              packages = with pkgs; [
                inputs'.deploy-rs.packages.default
                config.agenix-rekey.package
                nixfmt-tree
                nixd
              ];
            };
          };

        flake = {
          diskoConfigurations = {
            default = {
              imports = [
                disko.nixosModules.default
              ];

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
                      end = "512M";
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
            };
          };

          nixosModules = {
            hyperv-vm = {
              virtualisation.hypervGuest.enable = true;
            };

            common-bloat-module = { pkgs, ... }: {
              imports = [
                home-manager.nixosModules.default
              ];

              fonts.packages = with pkgs; [
                nerd-fonts.fira-code
              ];

              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.artur = {
                imports = [
                  nvf.homeManagerModules.default
                  self.homeModules.artur
                ];
                home = {
                  username = "artur";
                  homeDirectory = "/home/artur";
                  stateVersion = "25.11";
                  preferXdgDirectories = true;
                };
              };
            };

            common-nix-module =
              { pkgs, config, ... }:
              {
                imports = [
                  agenix.nixosModules.default
                  agenix-rekey.nixosModules.default
                ];

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
                  };
                  channel.enable = false;
                  optimise.automatic = true;
                  gc.automatic = true;
                };

                boot.kernelPackages = pkgs.linuxPackages_latest;
                boot.loader.systemd-boot.enable = true;
                boot.initrd.systemd.enable = true;

                networking.useDHCP = false;
                networking.networkmanager = {
                  enable = true;
                  settings = {
                    connection = {
                      "ipv4.clat" = "auto";
                    };
                  };
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

                age = {
                  rekey = {
                    storageMode = "local";
                    localStorageDir = ./. + "/rekeyed/${config.networking.hostName}";
                    masterIdentities = [
                      "/home/artur/.ssh/id_ed25519"
                    ];
                  };
                };

                services.openssh.enable = true;
                security.sudo.wheelNeedsPassword = false;

                time.timeZone = "Europe/Vienna";
                i18n.defaultLocale = "en_US.UTF-8";

                nixpkgs.config.allowUnfree = true;
                system.stateVersion = "25.11";
              };
          };

          nixosConfigurations = {
            nixos-development-environment-aarch64 = withSystem "aarch64-linux" (
              { system, ... }:
              nixpkgs.lib.nixosSystem {
                modules = [
                  self.diskoConfigurations.default
                  self.nixosModules.common-nix-module
                  self.nixosModules.common-bloat-module
                  self.nixosModules.artur
                  self.nixosModules.wm
                  self.nixosModules.umbriel
                  self.nixosModules.noctalia
                  {
                    networking.hostName = "nixos-development-environment-aarch64";
                    nixpkgs.hostPlatform = system;
                  }
                ];
              }
            );

            nixos-development-environment = withSystem "x86_64-linux" (
              { system, ... }:
              nixpkgs.lib.nixosSystem {
                modules = [
                  self.diskoConfigurations.default
                  self.nixosModules.common-nix-module
                  self.nixosModules.common-bloat-module
                  self.nixosModules.hyperv-vm
                  self.nixosModules.artur
                  self.nixosModules.wm
                  self.nixosModules.sway
                  self.nixosModules.sunshine
                  {
                    networking.hostName = "nixos-development-environment";
                    nixpkgs.hostPlatform = system;
                    age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDD0wl0FAPfCFuE13ul8D+5D1Zq4vrWQsRVF28aZgcgN";
                  }
                ];
              }
            );
          };
        };
      }
    );
}

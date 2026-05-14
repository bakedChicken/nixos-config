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

    agenix = {
      url = "github:ryantm/agenix";
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
      deploy-rs,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { withSystem, ... }:
      {
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

            devShells.default = pkgs.mkShellNoCC {
              packages = with pkgs; [
                inputs'.deploy-rs.packages.default
                inputs'.agenix.packages.default
                nixfmt-tree
                nil
              ];
            };

          };

        flake = {
          nixosModules = {
            physical-host =
              { pkgs, ... }:
              {
                boot.kernelPackages = pkgs.linuxPackages_latest;
                boot.loader.systemd-boot.enable = true;
                boot.initrd.systemd.enable = true;
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

                services.openssh.enable = true;
                networking.firewall.allowedTCPPorts = [ 22 ];
                security.sudo.wheelNeedsPassword = false;

                time.timeZone = "Europe/Vienna";
                i18n.defaultLocale = "en_US.UTF-8";

                nixpkgs.hostPlatform = "x86_64-linux";
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
            nixos-development-environment = withSystem "x86_64-linux" (
              { ... }:
              nixpkgs.lib.nixosSystem {
                modules = [
                  disko.nixosModules.default
                  home-manager.nixosModules.home-manager
                  self.nixosModules.common-nix-module
                  self.nixosModules.physical-host
                  self.nixosModules.hyperv-vm
                  self.nixosModules.artur
                  self.nixosModules.xserver
                  self.nixosModules.kde-desktop
                  {
                    networking.hostName = "nixos-development-environment";

                    services.pipewire.enable = false;
                    services.pulseaudio.enable = true;

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
                  }
                ];
              }
            );

            k8s-master-node = withSystem "x86_64-linux" (
              { ... }:
              nixpkgs.lib.nixosSystem {
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
              }
            );
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
        };
      }
    );
}

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
          agenix-rekey.flakeModules.default
          disko.flakeModules.default
          ./users
          ./gui
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
              nativeBuildInputs = [ config.agenix-rekey.package ];

              packages = with pkgs; [
                inputs'.deploy-rs.packages.default
                nixfmt-tree
                nil
              ];
            };
          };

        flake = {
          diskoConfigurations = {
            default = {
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
            };

            kubernetes-node-disk = {
              disko.devices.disk.main = {
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

          nixosModules = {
            physical-host =
              { pkgs, ... }:
              {
                boot.kernelPackages = pkgs.linuxPackages_latest;
                boot.loader.systemd-boot.enable = true;
                boot.initrd.systemd.enable = true;
                networking.useDHCP = true;
                systemd.network.config.networkConfig = {
                  IPv4Forwarding = true;
                  IPv6Forwarding = true;
                };
              };

            hyperv-vm = {
              virtualisation.hypervGuest.enable = true;
            };

            common-nix-module =
              { pkgs, config, ... }:
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

                age = {
                  rekey = {
                    storageMode = "local";
                    localStorageDir = ./. + "/secrets/rekeyed/${config.networking.hostName}";
                    masterIdentities = [
                      "/home/artur/.ssh/id_ed25519"
                    ];
                  };
                  secrets = {
                    kubernetes-join-token.rekeyFile = ./secrets/k3s/join-token.age;
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

            common-kubernetes-module =
              { config, ... }:
              {
                networking.firewall.allowedTCPPorts = [
                  80
                  443
                  6443 # Kubernetes API server
                  2379 # etcd
                  2380 # etcd
                  5001 # k3s registry
                ];
                networking.firewall.allowedUDPPorts = [
                  8472 # Flannel multi-node connection
                ];

                services.k3s = {
                  enable = true;
                  role = "server";
                  tokenFile = config.age.secrets.kubernetes-join-token.path;
                  extraFlags = toString [
                    "--write-kubeconfig-mode 0644"
                    "--disable servicelb"
                    "--disable local-storage"
                    "--disable traefik"
                  ];
                };
              };
          };

          nixosConfigurations = {
            nixos-development-environment = withSystem "x86_64-linux" (
              { ... }:
              nixpkgs.lib.nixosSystem {
                modules = [
                  disko.nixosModules.default
                  home-manager.nixosModules.default
                  agenix.nixosModules.default
                  agenix-rekey.nixosModules.default
                  self.diskoConfigurations.default
                  self.nixosModules.common-nix-module
                  self.nixosModules.physical-host
                  self.nixosModules.hyperv-vm
                  self.nixosModules.artur
                  self.nixosModules.kde-desktop
                  self.nixosModules.wayland
                  self.nixosModules.sunshine
                  {
                    networking.hostName = "nixos-development-environment";
                    networking.firewall.allowedTCPPorts = [ 3389 ];

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

                    age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDD0wl0FAPfCFuE13ul8D+5D1Zq4vrWQsRVF28aZgcgN";
                  }
                ];
              }
            );

            k8s-node-1 = withSystem "x86_64-linux" (
              { ... }:
              nixpkgs.lib.nixosSystem {
                modules = [
                  disko.nixosModules.default
                  agenix.nixosModules.default
                  agenix-rekey.nixosModules.default
                  self.diskoConfigurations.kubernetes-node-disk
                  self.nixosModules.common-nix-module
                  self.nixosModules.common-kubernetes-module
                  self.nixosModules.physical-host
                  self.nixosModules.hyperv-vm
                  self.nixosModules.artur
                  (
                    { config, ... }:
                    {
                      networking.hostName = "k8s-node-1";
                      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHKuyZKeptfbDWJZlPblXBYL0k8q+T1W2DoXaoTCfxMt";
                      services.k3s.clusterInit = true;
                    }
                  )
                ];
              }
            );

            k8s-node-2 = withSystem "x86_64-linux" (
              { ... }:
              nixpkgs.lib.nixosSystem {
                modules = [
                  disko.nixosModules.default
                  agenix.nixosModules.default
                  agenix-rekey.nixosModules.default
                  self.diskoConfigurations.kubernetes-node-disk
                  self.nixosModules.common-nix-module
                  self.nixosModules.common-kubernetes-module
                  self.nixosModules.physical-host
                  self.nixosModules.hyperv-vm
                  self.nixosModules.artur
                  (
                    { config, ... }:
                    {
                      networking.hostName = "k8s-node-2";
                      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDbPjrlPVJDTV4emcUgh3jYj9c9PnWM37JaDN7tBYoZ6";
                      services.k3s.serverAddr = "https://k8s-node-1.local:6443";
                    }
                  )
                ];
              }
            );

            k8s-node-3 = withSystem "x86_64-linux" (
              { ... }:
              nixpkgs.lib.nixosSystem {
                modules = [
                  disko.nixosModules.default
                  agenix.nixosModules.default
                  agenix-rekey.nixosModules.default
                  self.diskoConfigurations.kubernetes-node-disk
                  self.nixosModules.common-nix-module
                  self.nixosModules.common-kubernetes-module
                  self.nixosModules.physical-host
                  self.nixosModules.hyperv-vm
                  self.nixosModules.artur
                  (
                    { config, ... }:
                    {
                      networking.hostName = "k8s-node-3";
                      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICULfwiKvANMQLMfYz4Ozdo+mF/+AwZSnASJEnaVX9S3";
                      services.k3s.serverAddr = "https://k8s-node-1.local:6443";
                    }
                  )
                ];
              }
            );
          };

          deploy.nodes = {
            k8s-node-1 = {
              hostname = "k8s-node-1.local";
              sshUser = "artur";
              profiles.system = {
                user = "root";
                path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.k8s-node-1;
              };
            };
            k8s-node-2 = {
              hostname = "k8s-node-2.local";
              sshUser = "artur";
              profiles.system = {
                user = "root";
                path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.k8s-node-2;
              };
            };
            k8s-node-3 = {
              hostname = "k8s-node-3.local";
              sshUser = "artur";
              profiles.system = {
                user = "root";
                path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.k8s-node-3;
              };
            };
          };
        };
      }
    );
}

{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";

    nixos-raspberry-pi-uefi = {
      url = "github:bakedChicken/nixos-raspberry-pi-uefi";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    umbriel = {
      url = "git+https://github.com/noctalia-dev/umbriel";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    treefmt-nix,
    home-manager,
    nvf,
    flake-parts,
    disko,
    agenix,
    agenix-rekey,
    impermanence,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} (
      {withSystem, ...}: {
        imports = [
          treefmt-nix.flakeModule
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

        perSystem = {
          pkgs,
          inputs',
          ...
        }: {
          treefmt = {
            projectRootFile = "flake.nix";
            programs.prettier.enable = true;
            programs.alejandra.enable = true;
          };

          devShells.default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              inputs'.deploy-rs.packages.default
              inputs'.agenix-rekey.packages.default
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
                        mountOptions = ["umask=0077"];
                      };
                    };
                    root = {
                      size = "100%";
                      content = {
                        type = "btrfs";
                        extraArgs = ["-f"];
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
                          "/persist" = {
                            mountpoint = "/persist";
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

            qemu-vm = {modulesPath, ...}: {
              imports = ["${modulesPath}/profiles/qemu-guest.nix"];
              services.qemuGuest.enable = true;
            };

            ephemeral-root = {
              pkgs,
              utils,
              ...
            }: {
              imports = [
                impermanence.nixosModules.impermanence
              ];

              fileSystems."/persist".neededForBoot = true;
              fileSystems."/home".neededForBoot = true;

              environment.persistence."/persist" = {
                hideMounts = true;
                directories = [
                  "/var/lib/nixos"
                  "/var/lib/systemd"
                  "/var/lib/NetworkManager"
                  "/var/log"
                ];
                users.artur = {
                  directories = [
                    "Documents"
                    "Downloads"
                    {
                      directory = ".ssh";
                      mode = "0700";
                    }
                    ".config/mozilla"
                    ".local/share/direnv"
                    ".local/state/bash"
                  ];
                };
              };

              services.openssh.hostKeys = [
                {
                  path = "/persist/etc/ssh/ssh_host_ed25519_key";
                  type = "ed25519";
                }
                {
                  path = "/persist/etc/ssh/ssh_host_rsa_key";
                  type = "rsa";
                  bits = 4096;
                }
              ];
              age.identityPaths = ["/persist/etc/ssh/ssh_host_ed25519_key"];

              boot.initrd.systemd.tmpfiles.settings.ephemeral-root."/sysroot/etc".d = {
                mode = "0755";
                user = "root";
                group = "root";
              };

              boot.initrd.systemd.initrdBin = [pkgs.btrfs-progs];
              boot.initrd.systemd.services.wipe-ephemeral = {
                description = "Recreate / and /home as empty subvolumes";
                wantedBy = ["initrd.target"];
                requires = ["${utils.escapeSystemdPath "/dev/disk/by-partlabel/disk-main-root"}.device"];
                after = ["${utils.escapeSystemdPath "/dev/disk/by-partlabel/disk-main-root"}.device"];
                before = ["sysroot.mount"];
                unitConfig.DefaultDependencies = false;
                serviceConfig.Type = "oneshot";
                script = ''
                  mkdir -p /btrfs
                  mount -t btrfs -o subvolid=5 /dev/disk/by-partlabel/disk-main-root /btrfs
                  # A boot interrupted between delete and create leaves a subvolume missing; carry on and create it
                  btrfs subvolume delete --recursive /btrfs/root || true
                  btrfs subvolume delete --recursive /btrfs/home || true
                  btrfs subvolume create /btrfs/root
                  btrfs subvolume create /btrfs/home
                  umount /btrfs
                '';
              };
            };

            common-bloat-module = {pkgs, ...}: {
              imports = [
                home-manager.nixosModules.default
              ];

              fonts.packages = with pkgs; [
                nerd-fonts.fira-code
              ];

              age.secrets.ghcr-token = {
                rekeyFile = ./kubernetes/secrets/ghcr-token.age;
                owner = "artur";
                mode = "0400";
              };

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

            common-nix-module = {
              pkgs,
              config,
              ...
            }: {
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
                    "ipv4.clat" = 1; # auto
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

              documentation.enable = false;
              documentation.nixos.enable = false;

              nixpkgs.config.allowUnfree = true;
              system.stateVersion = "25.11";
            };
          };

          nixosConfigurations = {
            nixos-development-environment-aarch64 = withSystem "aarch64-linux" (
              {system, ...}:
                nixpkgs.lib.nixosSystem {
                  modules = [
                    self.diskoConfigurations.default
                    self.nixosModules.ephemeral-root
                    self.nixosModules.common-nix-module
                    self.nixosModules.common-bloat-module
                    self.nixosModules.artur
                    self.nixosModules.wm
                    self.nixosModules.umbriel
                    self.nixosModules.noctalia
                    {
                      networking.hostName = "nixos-development-environment-aarch64";
                      nixpkgs.hostPlatform = system;
                      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDD0wl0FAPfCFuE13ul8D+5D1Zq4vrWQsRVF28aZgcgN";
                    }
                  ];
                }
            );

            nixos-development-environment = withSystem "x86_64-linux" (
              {system, ...}:
                nixpkgs.lib.nixosSystem {
                  modules = [
                    self.diskoConfigurations.default
                    self.nixosModules.ephemeral-root
                    self.nixosModules.common-nix-module
                    self.nixosModules.common-bloat-module
                    self.nixosModules.hyperv-vm
                    self.nixosModules.artur
                    self.nixosModules.xserver
                    self.nixosModules.kde-desktop
                    {
                      networking.hostName = "nixos-development-environment";
                      nixpkgs.hostPlatform = system;
                      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMqP+nJMz3zHwDHZOfCNHDNgLhSqvjs5tgbxYVs6eu4X";
                    }
                  ];
                }
            );
          };
        };
      }
    );
}

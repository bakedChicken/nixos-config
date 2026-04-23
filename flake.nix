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

    colmena = {
      url = "github:zhaofengli/colmena";
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
      colmena,
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
        { pkgs, inputs', ... }:
        {
          formatter = pkgs.nixfmt-tree;

          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              inputs'.colmena.packages.colmena
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

          k0s-node-common = {
            services.k0s = {
              enable = true;
              role = "worker";
              spec.api.address = "172.16.30.50";
            };

            environment.etc = {
              "k0s/k0stoken" = {
                text = ''
                  H4sIAAAAAAAC/2xVy46zuBrc91PkBfofG5KeTqSz+Ak4CQlO2/gC3gFmmmBzaUJuPP1RZ3qkc6TZff6qXCVZVlXWn0Q5nE9du5pd4UthL+exHM6rl9fZz7x6mc1ms6IcxtNfpyIby9fsMlbdcBofrzobs9XsEIPxEMM15TpkJ8+nIuQxVyEBiNMnBsa1gWHMqUcD7BMpegWQG/PQU8AKBmArk96VtbKkEVzI3WPv9DjjIaYTGo6yrzWgVPL+kMM+zLaqZgZRym97YpGngQ6o0JhYtCUMCcrRnPFFFUHVS1vttehT3tzrkqEvKainuHKjrT1mJrgxQVXJYcCTHtMgrGhb3MrP/h8M/y/GeNiWgfoiQqwVWEhiEBYBTbSPVC7UIm2gjFCfsoSqyAhXORplHHpRoH3uou3a4jCtccC5WBOBBOEBiHkYaICe3Big6/ebcE4PfNs5sVVO2YqzMHeqXe+qaySVwXVpbJoH79cj392I4fscqqPcVFEKLM8TDdS2eiMu2mpA3Ojxfj249qtsvfPBgSJnwok2AHKED2KzfFMba3MXC+kX7mHSSRbcPwrT78WtD2kAv4gzrrNGRMctfiuZ52MW3nSgfNlgTuNlWgi9KxroK1jxrBEbYdBR2nCNEwsO4DykEh60rUJuFkJJcVvX+JEjPReNDY9BGBZTelVJf80MhdR8zglf9kzaa7mxmEmUUXcHmNSRAruJtr0qRBge+fstipeUNWpKrZJqG+yjrRjTRGwyhOLcWVayxWMGQ8qds6Nqz5MovEhpk4LjIUc2U8HoijqAhBGYB7TmzfuCT+geO52TCbxIpcXq1ntZQD80F0fcgKmo7VYm2CpWhaRZDFRioZl2cnNPhIvuCsCBBtU849bfA+jv3f5Mgd4TqTExyKNOTzMTemsDPRxoLxLC0K1G5LR0OReeBnZNmt7jQdgyq3bcwDWR6ZzykBNOPc4/r4zvbhQEdyFpoCBKiAk5ZmhTJr/3qWvmUhKX8PNQAPwmII2Eq5hM+rg06EgaPRSyGjJeLPTkff/BiRrkMYC9b/+YI8lqlekJ7QgM/eNW7DHppuMGPHKz7Ehtk2JT3XMg3Bimbh6oTjgqw21/ypqwKS32VG3vxVaPQmCv8H8PYnPfx21vcmBp1OidaIWNJtyva2/UtVBps7vTx3lOmgWPgDYZX37ENXrwTeUqYRfMF17m6uMBmhuX4sAM+ii21Zs6jRfRiluOBIiB7XLXG7VD9rpGxwjhr3wD5mkTPGIHucIoESN6yVxR5zA8crNwpFSTRp2TbZZnarpr2tDdASy4bjXKUQULgwGD4Z1Jdcxu/Y4Z42aob0tfWdnYpmRoe2TaL83yq4A43kOvibeeJEnV0rYfS97z2Oxc4adz2vQPze8wNqEpfOzH7e8hbb3r2iqTNn1C5P2NWbothA1wMHaRX5l4Q2Aej4xO3j0F+CQaelYCNYXQcO9+XpnsJiFto2FojptFmEsbs0QZ8njfY26j7DG6Hwzsf7IZMUM+CRCxCOwm5tgTAX/m8oF0/3kG/LkcruWwmlXj2J9Xf/wB/3R+wbdfLvi1AKu3+dx9mc3arClXMwPOL0XXjuV9/Lsn/p5/euKnNJ6s78Xl/Dxd8tKW42vedeN5HLL+/9Uuw1C24+s/Ss+lObV6NVt37V+nz5dvlafZz6V/kXsaPS3HzpTtanZZTkN9/jXZ+xL8aZewu0/zulq+/DcAAP//iqc3HPMGAAA=
                '';
                mode = "0440";
              };
            };

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
          generic-node = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit inputs; };
            modules = [
              self.colmenaHive.nodes.k8s-node-01
            ];
          };
        };

        colmenaHive = colmena.lib.makeHive {
          meta = {
            nixpkgs = import nixpkgs {
              system = "x86_64-linux";
              overlays = [
                k0s.overlays.default
              ];
            };

            specialArgs = { inherit inputs; };
          };

          defaults =
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

              services.avahi = {
                enable = true;
                nssmdns = true;
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

          nixos-development-environment =
            { name, ... }:
            {
              imports = [
                disko.nixosModules.default
                k0s.nixosModules.default
                self.nixosModules.physical-host
                self.nixosModules.hyperv-vm
                self.nixosModules.home-manager
                self.nixosModules.artur
                self.nixosModules.xserver
                self.nixosModules.kde-desktop
              ];
              deployment.allowLocalDeployment = true;
              networking.hostName = name;

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
            };

          k8s-master-node =
            { name, modulesPath, ... }:
            {
              imports = [
                "${modulesPath}/virtualisation/lxc-container.nix"
                k0s.nixosModules.default
                self.nixosModules.artur
              ];

              deployment = {
                targetHost = "${name}.local";
                targetUser = "artur";
                tags = [ "k8s" ];
              };

              networking.hostName = name;
              networking.firewall.allowedTCPPorts = [
                6443
                8080
                9443
                8132
                8133
              ];
              networking.firewall.allowedUDPPorts = [ 4789 ];

              services.k0s = {
                enable = true;
                role = "controller";
                controller.isLeader = true;
                spec = {
                  api = {
                    address = "172.16.30.50";
                    sans = [
                      "172.16.30.50"
                      "${name}.local"
                    ];
                  };
                  network = {
                    provider = "calico";
                  };
                };
              };
            };

          k8s-node-01 =
            { name, ... }:
            {
              imports = [
                disko.nixosModules.disko
                k0s.nixosModules.default
                self.nixosModules.physical-host
                self.nixosModules.hyperv-vm
                self.nixosModules.k0s-node-common
                self.nixosModules.artur
              ];
              deployment = {
                targetHost = "172.16.30.46";
                targetUser = "artur";
                tags = [ "k8s" ];
              };

              networking.hostName = name;
            };
        };
      };
    };
}

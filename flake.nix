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
                    kubernetes-cloudflare-api-token.rekeyFile = ./secrets/k3s/cloudflare-api-token.age;
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
              { pkgs, config, ... }:
              {
                networking = {
                  dhcpcd.denyInterfaces = [
                    "lxc*"
                    "cilium*"
                  ];

                  firewall = {
                    checkReversePath = false;

                    allowedTCPPorts = [
                      80
                      443
                      6443
                      2379
                      2380
                      4240
                      4244
                      4245
                      4250
                      6060
                      6061
                      6062
                      9878
                      9879
                      9890
                      9891
                      9833
                      9901
                      9962
                      9963
                      9964
                      10250
                    ];
                    allowedUDPPorts = [ 8472 ];
                  };
                };

                environment.variables = {
                  KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
                };

                environment.systemPackages = with pkgs; [
                  cilium-cli
                  k9s
                ];

                services.openiscsi = {
                  enable = true;
                  name = "iqn.2016-04.com.open-iscsi:${config.networking.hostName}";
                };

                services.k3s = {
                  enable = true;
                  role = "server";
                  tokenFile = config.age.secrets.kubernetes-join-token.path;
                  extraFlags = [
                    "--write-kubeconfig-mode 0644"
                    "--tls-san ${config.networking.hostName}.local"
                    "--tls-san k8s.burned.host"
                    "--tls-san 172.16.30.201"
                    "--cluster-cidr=10.42.0.0/16,fd42::/56"
                    "--service-cidr=10.43.0.0/16,fd43::/112"
                    "--flannel-backend=none"
                    "--disable-network-policy"
                    "--disable-kube-proxy"
                  ];
                  disable = [
                    "servicelb"
                    "traefik"
                    "local-storage"
                  ];
                  manifests = {
                    cloudflare-api-token.source = config.age.secrets.kubernetes-cloudflare-api-token.path;
                    cert-manager-cluster-issuer.source = ./kubernetes/manifests/cluster-issuer.yaml;
                    kube-vip.source = ./kubernetes/manifests/kube-vip.yaml;
                    gateway-api.source = pkgs.fetchurl {
                      url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/experimental-install.yaml";
                      hash = "sha256-8NXCsL7yudgLprqQnl5dveCABjhDdgg1P0Gm69OvzZ8=";
                    };
                  };
                  autoDeployCharts = {
                    cilium = {
                      repo = "oci://quay.io/cilium/charts/cilium";
                      version = "1.19.6";
                      hash = "sha256-IcQ89ThB+asDdQR9lapMZAUepSu9LGeUFuZAj18ckXk=";
                      targetNamespace = "kube-system";
                      extraFieldDefinitions = {
                        spec.bootstrap = true;
                      };
                      values = {
                        k8sServiceHost = "172.16.30.201";
                        k8sServicePort = "6443";
                        ipv6.enabled = true;
                        kubeProxyReplacement = true;
                        ipam.operator.clusterPoolIPv4PodCIDRList = [ "10.42.0.0/16" ];
                        ipam.operarot.clusterPoolIPv6PodCIDRList = [ "fd42::/56" ];
                        hubble.relay.enabled = true;
                        hubble.ui.enabled = true;
                        gatewayAPI = {
                          enabled = true;
                          enableAlpn = true;
                        };
                      };
                    };
                    cert-manager = {
                      repo = "oci://quay.io/jetstack/charts/cert-manager";
                      version = "v1.21.0";
                      hash = "sha256-nCxvq/PPj+FNrLAW83yBm2a8LHnot6zeRXPUXsFB+5c=";
                      targetNamespace = "cert-manager";
                      createNamespace = true;
                      extraFieldDefinitions = {
                        spec.bootstrap = true;
                      };
                      values = {
                        crds.enabled = true;
                        config.gatewayAPI.enabled = true;
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
                  ({ config, pkgs, ... }: {
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
                  })
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
                      services.k3s.clusterInit = true;
                      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILuKon1YzKGQsIvF3iaK82IJWiYxedxxg53dtbIOohdi";
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
                      services.k3s.serverAddr = "https://k8s-node-1.local:6443";
                      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPI1m281PP0VBICwapnd2Mb8P1ermxVaD5m4wwlXwbG7";
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
                      services.k3s.serverAddr = "https://k8s-node-1.local:6443";
                      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPq+y02LvSiN9zxFMaSROQ+elyXOMUAmeI8ZQsm82BDq";
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

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

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
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

    wrdp = {
      url = "git+ssh://git@github.com/bakedChicken/wrpd";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    treefmt-nix,
    home-manager,
    flake-parts,
    agenix-rekey,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} (
      {withSystem, ...}: {
        imports = [
          treefmt-nix.flakeModule
          home-manager.flakeModules.home-manager
          agenix-rekey.flakeModules.default
          ./hardware
          ./os
          ./roles
          ./users
          ./kubernetes
        ];

        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
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
          nixosConfigurations = {
            nixos-development-environment = withSystem "x86_64-linux" (
              {system, ...}:
                nixpkgs.lib.nixosSystem {
                  modules = [
                    self.diskoConfigurations.vm
                    self.nixosModules.hyperv-vm
                    self.nixosModules.base
                    self.nixosModules.ephemeral
                    self.nixosModules.workstation
                    self.nixosModules.desktop-kde
                    self.nixosModules.artur
                    self.nixosModules.artur-workstation
                    inputs.wrdp.nixosModules.dev-vm
                    {environment.persistence."/persist".directories = ["/var/lib/wrdp-broker"];}
                    {
                      networking.hostName = "nixos-development-environment";
                      nixpkgs.hostPlatform = system;
                      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMqP+nJMz3zHwDHZOfCNHDNgLhSqvjs5tgbxYVs6eu4X";
                    }
                  ];
                }
            );
          };

          darwinConfigurations = {
            yoba-book-pro = withSystem "aarch64-darwin" (
              {system, ...}:
                inputs.nix-darwin.lib.darwinSystem {
                  modules = [
                    self.darwinModules.darwin
                    self.darwinModules.workstation
                    self.darwinModules.builder
                    self.darwinModules.yoba
                    {
                      networking.hostName = "yoba-book-pro";
                      nixpkgs.hostPlatform = system;
                      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExu++Nvakt+IOMsjbgCkf5u5FrJrYCCijJWHODDpHGe";
                    }
                  ];
                }
            );
          };
        };

        kubernetes.clusters = {
          main = {
            domain = "burned.host";
            internalDomain = "internal.k8s.burned.host";
            init = "k8s-node-2";
            tokenFile = ./kubernetes/secrets/join-token.age;
            loadBalancerPool = [
              {cidr = "172.16.33.200/32";}
            ];
            storage.dataset = "tank/kubernetes";
            storage.csiDriverConfig = ./kubernetes/secrets/democratic-csi-config-main.age;
            modules = with self.nixosModules; [
              cilium
              kube-vip
              openbao
              argocd
            ];
            nodes = {
              k8s-node-1 = {
                role = "server";
                system = "x86_64-linux";
                hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBgayw+LEcOM0N62lRmY67rwsut5AlQzH7s30qi1/uKE";
                modules = [
                  self.diskoConfigurations.vm
                  self.nixosModules.hyperv-vm
                  self.nixosModules.ephemeral
                ];
              };
              k8s-node-2 = {
                role = "server";
                system = "x86_64-linux";
                hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILg/ncWfxWXZX4oLFq13dgzcNoOyurb+fkicj4E4G9MC";
                modules = [
                  self.diskoConfigurations.vm
                  self.nixosModules.hyperv-vm
                  self.nixosModules.ephemeral
                ];
              };
              k8s-node-3 = {
                role = "server";
                system = "x86_64-linux";
                hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICsEqPnBF3JpXgFLVa37SjdKyiOBAbrj1KDtb9dSH/44";
                modules = [
                  self.diskoConfigurations.vm
                  self.nixosModules.hyperv-vm
                  self.nixosModules.ephemeral
                ];
              };
            };
          };

          edge = {
            domain = "edge.burned.host";
            internalDomain = "internal.edge.burned.host";
            init = "storage-station";
            tokenFile = ./kubernetes/secrets/edge-join-token.age;
            storage.dataset = "tank/kubernetes-edge";
            storage.csiDriverConfig = ./kubernetes/secrets/democratic-csi-config-edge.age;
            ca = {
              cert = ./kubernetes/secrets/edge-ca-crt.age;
              key = ./kubernetes/secrets/edge-ca-key.age;
            };
            modules = with self.nixosModules; [
              flannel
              argocd-spoke
              mktxp
              cloudflare-token
            ];
            nodes = {
              storage-station = {
                role = "server";
                system = "x86_64-linux";
                hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPGl/IHpSEQ7w4By0Rbzeik857lXvoj+zK+XYCOQsOwf";
                modules = [
                  self.nixosModules.storage-station-hardware
                  self.nixosModules.ephemeral
                  self.nixosModules.nas
                  self.nixosModules.storage-server
                  self.nixosModules.builder
                  self.nixosModules.tatyana
                  {
                    fileSystems."/home/artur" = {
                      device = "tank/home/artur";
                      fsType = "zfs";
                      options = ["nofail"];
                    };
                    users.users.artur.extraGroups = [
                      "designers"
                      "apps"
                    ];

                    services.k3s.extraFlags = [
                      "--node-label=storage.burned.host/zfs=true"
                      "--node-label=svccontroller.k3s.cattle.io/enablelb=true"
                      "--kubelet-arg=allowed-unsafe-sysctls=net.ipv4.ip_forward,net.ipv6.conf.all.forwarding,net.ipv6.conf.all.disable_ipv6"
                      "--node-ip=172.16.33.53,fd71:895d:e328:33:9cd1:e6ff:febf:576e"
                    ];
                    # Traefik comes from Argo CD (platform/edge), not k3s
                    services.k3s.disable = ["traefik"];
                  }
                ];
              };
              k8s-node-aarch64-1 = {
                role = "agent";
                system = "aarch64-linux";
                hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID0s5TvAii/foOw3yNLcvHURHZPL+j4p1HwvbgP3ea1X";
                modules = [self.nixosModules.raspberry-pi-3];
              };
              k8s-node-aarch64-2 = {
                role = "agent";
                system = "aarch64-linux";
                hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJK6Befn24tvAQ9f+nPX3giRZB2mVfggSX2CCdhnE4Ss";
                modules = [self.nixosModules.raspberry-pi-3];
              };
            };
          };
        };
      }
    );
}

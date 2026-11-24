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
      inputs.flake-parts.follows = "flake-parts";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    wrdp = {
      url = "git+ssh://git@github.com/bakedChicken/wrdp";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    hq = {
      url = "git+ssh://git@github.com/bakedChicken/hq";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.treefmt-nix.follows = "treefmt-nix";
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
      {...}: {
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
          "aarch64-darwin"
        ];

        perSystem = {
          pkgs,
          inputs',
          ...
        }: {
          treefmt = {
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
            nixos-development-environment = nixpkgs.lib.nixosSystem {
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
                  nixpkgs.hostPlatform = "x86_64-linux";
                  age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMqP+nJMz3zHwDHZOfCNHDNgLhSqvjs5tgbxYVs6eu4X";
                }
              ];
            };

            k8s-node-aarch64-1 = nixpkgs.lib.nixosSystem {
              modules = [
                self.nixosModules.raspberry-pi-3
                self.nixosModules.base
                self.nixosModules.artur
                {
                  networking.hostName = "k8s-node-aarch64-1";
                  nixpkgs.hostPlatform = "aarch64-linux";
                  age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID0s5TvAii/foOw3yNLcvHURHZPL+j4p1HwvbgP3ea1X";
                }
              ];
            };
          };

          deploy.nodes = {
            k8s-node-aarch64-1 = {
              hostname = self.nixosConfigurations.k8s-node-aarch64-1.config.networking.fqdn;
              sshUser = "artur";
              profiles.system = {
                user = "root";
                path = inputs.deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.k8s-node-aarch64-1;
              };
            };
          };

          darwinConfigurations = {
            yoba-book-pro = inputs.nix-darwin.lib.darwinSystem {
              modules = [
                self.darwinModules.darwin
                self.darwinModules.workstation
                self.darwinModules.builder
                self.darwinModules.yoba
                inputs.hq.darwinModules.default
                {
                  networking.hostName = "yoba-book-pro";
                  nixpkgs.hostPlatform = "aarch64-darwin";
                  age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExu++Nvakt+IOMsjbgCkf5u5FrJrYCCijJWHODDpHGe";
                }
              ];
            };
          };
        };

        kubernetes.clusters = {
          main = {
            domain = "burned.host";
            internalDomain = "internal.k8s.burned.host";
            init = "k8s-node-1";
            embeddedEtcd = true;
            tokenFile = ./kubernetes/secrets/join-token.age;
            loadBalancerPool = [
              {cidr = "fd71:895d:e328:33::200/128";}
            ];
            storage.dataset = "tank/kubernetes";
            storage.postgresDataset = "tank/kubernetes-postgres";
            storage.csiDriverConfig = ./kubernetes/secrets/democratic-csi-config-main.age;
            modules = with self.nixosModules; [
              cilium
              kube-vip
              postgres-storage
              openbao
              argocd
              {networking.firewall.allowedTCPPorts = [2379 2380];}
            ];
            nodes = {
              k8s-node-1 = {
                system = "x86_64-linux";
                hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBgayw+LEcOM0N62lRmY67rwsut5AlQzH7s30qi1/uKE";
                modules = [
                  self.diskoConfigurations.vm
                  self.nixosModules.hyperv-vm
                  self.nixosModules.ephemeral
                  {services.k3s.extraFlags = ["--node-ip=fd71:895d:e328:33:215:5dff:fe34:a44c"];}
                ];
              };
              k8s-node-2 = {
                system = "x86_64-linux";
                hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILg/ncWfxWXZX4oLFq13dgzcNoOyurb+fkicj4E4G9MC";
                modules = [
                  self.diskoConfigurations.vm
                  self.nixosModules.hyperv-vm
                  self.nixosModules.ephemeral
                  {services.k3s.extraFlags = ["--node-ip=fd71:895d:e328:33:215:5dff:fe34:a44d"];}
                ];
              };
              k8s-node-3 = {
                system = "x86_64-linux";
                hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICsEqPnBF3JpXgFLVa37SjdKyiOBAbrj1KDtb9dSH/44";
                modules = [
                  self.diskoConfigurations.vm
                  self.nixosModules.hyperv-vm
                  self.nixosModules.ephemeral
                  {services.k3s.extraFlags = ["--node-ip=fd71:895d:e328:33:215:5dff:fe34:a44f"];}
                ];
              };
            };
          };

          edge = {
            domain = "edge.burned.host";
            internalDomain = "internal.edge.burned.host";
            init = "storage-station";
            embeddedEtcd = false;
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
                system = "x86_64-linux";
                hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPGl/IHpSEQ7w4By0Rbzeik857lXvoj+zK+XYCOQsOwf";
                modules = [
                  self.diskoConfigurations.storage-station
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
                      "--node-ip=fd71:895d:e328:33:e0a0:2eff:fee0:f13"
                    ];
                    services.k3s.disable = ["traefik"];
                  }
                ];
              };
            };
          };
        };
      }
    );
}

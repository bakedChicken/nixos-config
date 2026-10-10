{
  self,
  inputs,
  lib,
  config,
  withSystem,
  ...
}: let
  inherit (lib) mkOption types;
  cfg = config.kubernetes;
in {
  imports = [
    ./addons.nix
  ];

  options.kubernetes.clusters = mkOption {
    description = "Kubernetes clusters, each with its nodes";
    type = types.attrsOf (types.submodule {
      options = {
        domain = mkOption {
          type = types.str;
          description = "Public domain: tls-san, <app>.<domain>";
        };
        internalDomain = mkOption {
          type = types.str;
          description = "LAN/VPN-only domain: <app>.<internalDomain>";
        };
        init = mkOption {
          type = types.str;
          description = "Server that initialises the cluster every other node joins it at <init>.local";
        };
        families = mkOption {
          type = types.listOf (types.enum ["ipv4" "ipv6"]);
          default = ["ipv4" "ipv6"];
          description = "IP families, primary first. Changing it means reinstalling the cluster";
        };
        clusterCidr = mkOption {
          type = types.attrsOf types.str;
          default = {
            ipv4 = "10.42.0.0/16";
            ipv6 = "fd42::/56";
          };
        };
        serviceCidr = mkOption {
          type = types.attrsOf types.str;
          default = {
            ipv4 = "10.43.0.0/16";
            ipv6 = "fd43::/112";
          };
        };
        tokenFile = mkOption {
          type = types.path;
          description = "agenix-rekey source of the join token";
        };
        loadBalancerPool = mkOption {
          type = types.listOf (types.attrsOf types.str);
          default = [];
          description = "Blocks of the CiliumLoadBalancerIPPool, as written in its spec";
        };
        storage.parentDataset = mkOption {
          type = types.str;
          description = "TrueNAS dataset holding this cluster's volumes; never shared between clusters";
        };
        ca = mkOption {
          type = types.nullOr (types.submodule {
            options = {
              cert = mkOption {type = types.path;};
              key = mkOption {type = types.path;};
            };
          });
          default = null;
          description = "Pre-generated CA (agenix-encrypted) k3s uses as both its server and client CA, so other clusters can trust and log in to this one; k3s only takes it before its first start";
        };
        modules = mkOption {
          type = types.listOf types.deferredModule;
          default = [];
          description = "NixOS modules (add-ons) for every node of the cluster";
        };
        nodes = mkOption {
          type = types.attrsOf (types.submodule {
            options = {
              role = mkOption {type = types.enum ["server" "agent"];};
              system = mkOption {type = types.enum ["x86_64-linux" "aarch64-linux"];};
              hostPubkey = mkOption {type = types.str;};
              modules = mkOption {
                type = types.listOf types.deferredModule;
                default = [];
                description = "NixOS modules for this machine only: hardware, disks";
              };
            };
          });
        };
      };
    });
  };

  config.kubernetes.clusters = {
    main = {
      domain = "burned.host";
      internalDomain = "internal.k8s.burned.host";
      init = "k8s-node-1";
      tokenFile = ./secrets/join-token.age;
      loadBalancerPool = [
        {cidr = "172.16.33.200/32";}
      ];
      storage.parentDataset = "tank/kubernetes";
      modules = with self.nixosModules; [
        gateway-api-crds
        snapshot-crds
        cilium
        kube-vip
        truenas-csi
        openbao
        argocd
      ];
      nodes = {
        k8s-node-1 = {
          role = "server";
          system = "x86_64-linux";
          hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBgayw+LEcOM0N62lRmY67rwsut5AlQzH7s30qi1/uKE";
          modules = with self.nixosModules; [
            hyperv-vm
            vm-disk
          ];
        };
        k8s-node-2 = {
          role = "server";
          system = "x86_64-linux";
          hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILg/ncWfxWXZX4oLFq13dgzcNoOyurb+fkicj4E4G9MC";
          modules = with self.nixosModules; [
            hyperv-vm
            vm-disk
          ];
        };
        k8s-node-3 = {
          role = "server";
          system = "x86_64-linux";
          hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICsEqPnBF3JpXgFLVa37SjdKyiOBAbrj1KDtb9dSH/44";
          modules = with self.nixosModules; [
            hyperv-vm
            vm-disk
          ];
        };
      };
    };

    edge = {
      domain = "edge.burned.host";
      internalDomain = "internal.edge.burned.host";
      init = "k8s-node-x86-64-1";
      tokenFile = ./secrets/edge-join-token.age;
      storage.parentDataset = "tank/kubernetes-edge";
      ca = {
        cert = ./secrets/edge-ca-crt.age;
        key = ./secrets/edge-ca-key.age;
      };
      modules = with self.nixosModules; [
        gateway-api-crds
        snapshot-crds
        flannel
        truenas-csi
        argocd-spoke
        mktxp
      ];
      nodes = {
        k8s-node-x86-64-1 = {
          role = "server";
          system = "x86_64-linux";
          hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDvQMlh94ENInyK8lViex3F7PFkaICrpvf3Xr5E0/Hx3";
          modules = with self.nixosModules; [
            qemu-vm
            vm-disk
            {disko.devices.disk.main.device = "/dev/vda";}
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

  config.flake = {
    nixosModules.kubernetes-node = {
      config,
      lib,
      pkgs,
      ...
    }: let
      cluster = config.kubernetes.cluster;
      isServer = config.kubernetes.role == "server";
      isInit = config.networking.hostName == cluster.init;
    in {
      options.kubernetes = {
        clusterName = lib.mkOption {type = lib.types.str;};
        cluster = lib.mkOption {type = lib.types.raw;};
        role = lib.mkOption {type = lib.types.enum ["server" "agent"];};
      };

      options.services.k3s.manifests = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
          config.target = lib.mkOverride 900 "nixos/${name}.yaml";
        }));
      };

      options.services.k3s.autoDeployCharts = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          config.enable = lib.mkOverride 900 false;
        });
      };

      config = {
        systemd.tmpfiles.rules = lib.mkIf isServer [
          "R /var/lib/rancher/k3s/server/manifests/nixos - - - - -"
        ];

        services.k3s.manifests = lib.mapAttrs (name: chart: {source = chart.source;}) config.services.k3s.autoDeployCharts;
        services.k3s.charts = lib.mapAttrs (name: chart: chart.package) config.services.k3s.autoDeployCharts;

        boot.kernelModules = [
          "iptables_nat"
          "iptables_filter"
          "iptables6_nat"
          "iptables6_filter"
        ];

        networking = {
          usePredictableInterfaceNames = false;
          tempAddresses = "disabled";
          networkmanager = {
            unmanaged = [
              "interface-name:lxc*"
              "interface-name:cilium*"
              "interface-name:flannel*"
              "interface-name:cni*"
              "interface-name:veth*"
            ];
            settings.connection = {
              "ipv4.dhcp-client-id" = "mac";
              "ipv4.dhcp-ipv6-only-preferred" = 2; # auto
              "ipv6.addr-gen-mode" = 0; # eui64
              "ipv6.ip6-privacy" = 0;
              "ipv6.dhcp-duid" = "ll";
            };
          };
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
              9878
              9879
              9890
              9891
              9963
              9964
              9100
              10250
            ];
            allowedUDPPorts = [
              8472
            ];
          };
        };

        services.avahi.allowInterfaces = ["eth0"];

        environment.variables = {
          KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
        };

        environment.systemPackages = with pkgs; [
          k9s
          kubectl
          kubectl-cnpg
          kubernetes-helm
        ];

        age.secrets.join-token = {
          rekeyFile = cluster.tokenFile;
          generator.script = "alnum";
        };

        services.k3s = {
          enable = true;
          role = config.kubernetes.role;
          tokenFile = config.age.secrets.join-token.path;
          clusterInit = isInit && lib.length (lib.filter (node: node.role == "server") (lib.attrValues cluster.nodes)) > 1;
          serverAddr = lib.mkIf (!isInit) "https://${cluster.init}.local:6443";
          disable = lib.mkIf isServer [
            "traefik"
            "servicelb"
          ];
          extraFlags = lib.mkIf isServer [
            "--write-kubeconfig-mode 0644"
            "--tls-san ${config.networking.hostName}.local"
            "--tls-san ${cluster.domain}"
            "--cluster-cidr=${lib.concatMapStringsSep "," (family: cluster.clusterCidr.${family}) cluster.families}"
            "--service-cidr=${lib.concatMapStringsSep "," (family: cluster.serviceCidr.${family}) cluster.families}"
          ];
        };
      };
    };

    nixosConfigurations = lib.concatMapAttrs (clusterName: cluster:
      lib.mapAttrs (nodeName: node:
        withSystem node.system ({system, ...}:
          inputs.nixpkgs.lib.nixosSystem {
            modules =
              [
                self.nixosModules.common-nix-module
                self.nixosModules.artur
                self.nixosModules.kubernetes-node
                {
                  networking.hostName = nodeName;
                  nixpkgs.hostPlatform = system;
                  age.rekey.hostPubkey = node.hostPubkey;
                  kubernetes = {
                    inherit clusterName cluster;
                    role = node.role;
                  };
                }
              ]
              ++ node.modules
              ++ cluster.modules;
          }))
      cluster.nodes)
    cfg.clusters;

    deploy.nodes = lib.concatMapAttrs (clusterName: cluster:
      lib.mapAttrs (nodeName: node: {
        hostname = "${nodeName}.local";
        sshUser = "artur";
        profiles.system = {
          user = "root";
          path = inputs.deploy-rs.lib.${node.system}.activate.nixos self.nixosConfigurations.${nodeName};
        };
      })
      cluster.nodes)
    cfg.clusters;
  };
}

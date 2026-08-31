{
  self,
  inputs,
  withSystem,
  ...
}:
{
  flake = {
    diskoConfigurations = {
      kubernetes-node-disk = {
        imports = [
          inputs.disko.nixosModules.default
        ];
        
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
      common-kubernetes-module =
        { pkgs, config, ... }:
        {
          boot.kernelModules = [
            "iptables_nat"
            "iptables_filter"
            "iptables6_nat"
            "iptables6_filter"
            "nvme-tcp"
          ];

          age.secrets = {
            join-token.rekeyFile = ./secrets/join-token.age;
            cloudflare-api-token.rekeyFile = ./secrets/cloudflare-api-token.age;
            truenas-api-key.rekeyFile = ./secrets/truenas-api-key.age;
          };

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
                9878
                9879
                9890
                9891
                9963
                9964
                10250
              ];
              allowedUDPPorts = [
                8472
              ];
            };
          };

          environment.variables = {
            KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
          };

          environment.systemPackages = with pkgs; [
            k9s
            kubectl
            kubectl-cnpg
            kubernetes-helm
          ];

          services.k3s = {
            enable = true;
            role = "server";
            tokenFile = config.age.secrets.join-token.path;
            extraFlags = [
              "--write-kubeconfig-mode 0644"
              "--tls-san ${config.networking.hostName}.local"
              "--tls-san ${config.networking.hostName}.internal.burned.host"
              "--tls-san burned.host"
              "--tls-san 172.16.30.200"
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
              # CRDs for Gateway API
              gateway-api.source = pkgs.fetchurl {
                url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/experimental-install.yaml";
                hash = "sha256-8NXCsL7yudgLprqQnl5dveCABjhDdgg1P0Gm69OvzZ8=";
              };
              cloudflare-api-token.source = config.age.secrets.cloudflare-api-token.path;
              truenas-api-key.source = config.age.secrets.truenas-api-key.path;
              cert-manager-cluster-issuer.source = ./manifests/cluster-issuer.yaml;
              cluster-ip-pool.source = ./manifests/cluster-ip-pool.yaml;
              kube-vip.source = ./manifests/kube-vip.yaml;
              gateway.source = ./manifests/gateway.yaml;
              postgres-cluster.source = ./manifests/postgres-cluster.yaml;
            };
            autoDeployCharts = {
              cilium = {
                repo = "oci://quay.io/cilium/charts/cilium";
                version = "1.21.0-pre.0";
                hash = "sha256-uQ+ba2fVZp0UP/GPUByvhWwiBinOrMFJ9Zd7H6irIS4=";
                targetNamespace = "kube-system";
                extraFieldDefinitions = {
                  spec.bootstrap = true;
                };
                values = {
                  k8sServiceHost = "172.16.30.201";
                  k8sServicePort = "6443";
                  ipv6.enabled = true;
                  routingMode = "native";
                  autoDirectNodeRoutes = true;
                  ipv4NativeRoutingCIDR = "10.42.0.0/16";
                  ipv6NativeRoutingCIDR = "fd42::/56";
                  ipam.mode = "cluster-pool";
                  ipam.operator.clusterPoolIPv4PodCIDRList = [ "10.42.0.0/16" ];
                  ipam.operator.clusterPoolIPv4MaskSize = 24;
                  ipam.operator.clusterPoolIPv6PodCIDRList = [ "fd42::/56" ];
                  ipam.operator.clusterPoolIPv6MaskSize = 64;
                  extraConfig.enable-ipv6-ndp = "true";
                  extraConfig.ipv6-mcast-device = "eth0";
                  kubeProxyReplacement = true;
                  hubble.relay.enabled = true;
                  gatewayAPI = {
                    enabled = true;
                    enableAlpn = true;
                  };
                  hubble.ui = {
                    enabled = true;
                    httpRoute = {
                      enabled = true;
                      hostnames = [ "hubble.burned.host" ];
                      parentRefs = [
                        {
                          name = "burned-gateway";
                          namespace = "gateway-system";
                          sectionName = "wildcard-https";
                        }
                      ];
                    };
                  };
                };
              };
              cert-manager = {
                repo = "oci://quay.io/jetstack/charts/cert-manager";
                version = "v1.21.1";
                hash = "sha256-wnEB8/PiNJ+0qecEMWEFv3tSrXO4yCV9NJjvfy9qStw=";
                targetNamespace = "cert-manager";
                createNamespace = true;
                extraFieldDefinitions = {
                  spec.bootstrap = true;
                };
                values = {
                  crds.enabled = true;
                  config.gatewayAPI.enabled = true;
                  config.gatewayAPI.enableListenerSet = true;
                  config.featureGates.ListenerSets = true;
                };
              };
              tns-csi = {
                repo = "oci://registry-1.docker.io/bfenski/tns-csi-driver";
                version = "0.17.6";
                hash = "sha256-afc86SIav9UL205aYE8Su1DufJF3ot7i1iT0RXK8CTA=";
                targetNamespace = "kube-system";
                extraFieldDefinitions = {
                  spec.bootstrap = true;
                };
                values = {
                  truenas = {
                    existingSecret = "truenas-api-key";
                    skipTLSVerify = true;
                  };
                  storageClasses = [
                    {
                      enabled = true;
                      name = "tns-csi-nvmeof";
                      protocol = "nvmeof";
                      pool = "tank";
                      parentDataset = "tank/kubernetes";
                      isDefault = true;
                      server = "172.16.30.53";
                    }
                  ];
                };
              };
              cloudnativepg = {
                repo = "oci://ghcr.io/cloudnative-pg/charts/cloudnative-pg";
                version = "0.29.0";
                hash = "sha256-Zo4GX/U1CNWCOHiP01s1WpJQYIQ2KalR3w5qk2Lm0y8=";
                targetNamespace = "postgres";
                createNamespace = true;
              };
            };
          };
        };
    };

    nixosConfigurations = {
      k8s-node-1 = withSystem "x86_64-linux" (
        { ... }:
        inputs.nixpkgs.lib.nixosSystem {
          modules = [
            self.nixosModules.common-nix-module
            self.nixosModules.common-kubernetes-module
            self.nixosModules.hyperv-vm
            self.nixosModules.artur
            {
              networking.hostName = "k8s-node-1";
              services.k3s.clusterInit = true;
              age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBgayw+LEcOM0N62lRmY67rwsut5AlQzH7s30qi1/uKE";
            }
          ];
        }
      );

      k8s-node-2 = withSystem "x86_64-linux" (
        { ... }:
        inputs.nixpkgs.lib.nixosSystem {
          modules = [
            self.diskoConfigurations.kubernetes-node-disk
            self.nixosModules.common-nix-module
            self.nixosModules.common-kubernetes-module
            self.nixosModules.hyperv-vm
            self.nixosModules.artur
            {
              networking.hostName = "k8s-node-2";
              services.k3s.serverAddr = "https://k8s-node-1.local:6443";
              age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILg/ncWfxWXZX4oLFq13dgzcNoOyurb+fkicj4E4G9MC";
            }
          ];
        }
      );

      k8s-node-3 = withSystem "x86_64-linux" (
        { ... }:
        inputs.nixpkgs.lib.nixosSystem {
          modules = [
            self.diskoConfigurations.kubernetes-node-disk
            self.nixosModules.common-nix-module
            self.nixosModules.common-kubernetes-module
            self.nixosModules.hyperv-vm
            self.nixosModules.artur
            {
              networking.hostName = "k8s-node-3";
              services.k3s.serverAddr = "https://k8s-node-1.local:6443";
              age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICsEqPnBF3JpXgFLVa37SjdKyiOBAbrj1KDtb9dSH/44";
            }
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

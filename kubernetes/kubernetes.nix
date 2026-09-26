{
  self,
  inputs,
  withSystem,
  ...
}: {
  # Push kubernetes/platform from the working tree to ghcr.io, where Argo CD syncs it from.
  perSystem = {pkgs, ...}: {
    apps.push-platform = {
      type = "app";
      program = pkgs.lib.getExe (pkgs.writeShellApplication {
        name = "push-platform";
        runtimeInputs = [pkgs.oras pkgs.git];
        text = ''
          token=/run/agenix/ghcr-token
          if [ ! -r "$token" ]; then
            echo "$token is missing: rebuild this machine with the ghcr-token agenix secret" >&2
            exit 1
          fi
          cd "$(git rev-parse --show-toplevel)/kubernetes/platform"
          dirty=false
          if [ -n "$(git status --porcelain -- .)" ]; then
            dirty=true
          fi
          oras push --username bakedchicken --password-stdin \
            --annotation "org.opencontainers.image.source=https://github.com/bakedchicken/nixos-config" \
            --annotation "org.opencontainers.image.revision=$(git rev-parse HEAD)" \
            --annotation "host.burned.dirty=$dirty" \
            ghcr.io/bakedchicken/homelab-platform:latest . < "$token"
        '';
      });
    };
  };

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
                  mountOptions = ["umask=0077"];
                };
              };
              root = {
                size = "100%";
                content = {
                  type = "btrfs";
                  extraArgs = ["-f"];
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
      common-kubernetes-module = {
        pkgs,
        config,
        ...
      }: {
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
          openbao-seal-key.rekeyFile = ./secrets/openbao-seal-key.age;
          argocd-ghcr-creds.rekeyFile = ./secrets/argocd-ghcr-credentials.age;
        };

        services.avahi.allowInterfaces = ["eth0"];

        # It's not documented anywhere, but apparantely TrueNAS can only ingest 1M writes over NVMe-oF
        services.udev.extraRules = ''
          ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="nvme*n*", ATTR{queue/max_sectors_kb}="1024"
        '';

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
            # TODO: This DNS name doesn't really exist, but it might be useful in case I have IPv6
            "--tls-san ${config.networking.hostName}.internal.burned.host"
            "--tls-san burned.host"
            "--tls-san 172.16.30.200"
            "--tls-san 172.16.30.201"
            # TODO: Would be nice to switch to IPv6-mostly/only
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
          manifests = let
            commandDependencies = {
              nativeBuildInputs = [
                pkgs.kubectl
              ];
            };
          in {
            # CRDs for Gateway API
            gateway-api.source = pkgs.fetchurl {
              url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/experimental-install.yaml";
              hash = "sha256-8NXCsL7yudgLprqQnl5dveCABjhDdgg1P0Gm69OvzZ8=";
            };
            # CRDs for making persistent volume snaphots, will be used with TrueNAS ZFS
            volume-snapshot-crds.source = let
              src = pkgs.fetchFromGitHub {
                owner = "kubernetes-csi";
                repo = "external-snapshotter";
                rev = "v8.6.0";
                hash = "sha256-9WSflI44XhecRqBWGKDfeMMHqOBwyInX9w2qMLDPylA=";
              };
            in
              pkgs.runCommand "volume-snapshot-crds.yaml" commandDependencies ''
                kubectl kustomize -o $out ${src}/client/config/crd
                echo "---" >> $out
                kubectl kustomize ${src}/deploy/kubernetes/snapshot-controller >> $out
              '';
            cloudflare-api-token.source = config.age.secrets.cloudflare-api-token.path;
            truenas-api-key.source = config.age.secrets.truenas-api-key.path;
            openbao-seal-key.source = config.age.secrets.openbao-seal-key.path;
            argocd-ghcr-creds.source = config.age.secrets.argocd-ghcr-creds.path;
            cluster-ip-pool.source = ./infra/cluster-ip-pool.yaml;
            kube-vip.source = ./infra/kube-vip.yaml;
            argocd-bootstrap.source = ./infra/argocd-bootstrap.yaml;
          };
          autoDeployCharts = {
            cilium = {
              repo = "oci://quay.io/cilium/charts/cilium";
              version = "1.21.0-pre.2";
              hash = "sha256-t09VSVgfyxKG9N+6Ip8zGwd9U+MRH0vIM9uPUI0UhR4=";
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
                ipam.operator.clusterPoolIPv4PodCIDRList = ["10.42.0.0/16"];
                ipam.operator.clusterPoolIPv4MaskSize = 24;
                ipam.operator.clusterPoolIPv6PodCIDRList = ["fd42::/56"];
                ipam.operator.clusterPoolIPv6MaskSize = 64;
                extraConfig.enable-ipv6-ndp = "true";
                extraConfig.ipv6-mcast-device = "eth0";
                kubeProxyReplacement = true;
                hubble.relay.enabled = true;
                gatewayAPI = {
                  enabled = true;
                  enableAlpn = true;
                };
                hubble.ui.enabled = true;
                hubble.ui.httpRoute = {
                  enabled = true;
                  parentRefs = [
                    {
                      name = "burned-gateway";
                      namespace = "gateway-system";
                      sectionName = "internal-https";
                    }
                  ];
                  hostnames = ["hubble.internal.k8s.burned.host"];
                };
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
                snapshots.enabled = true;
                storageClasses = [
                  {
                    enabled = true;
                    name = "tns-csi-nvmeof";
                    protocol = "nvmeof";
                    pool = "tank";
                    parentDataset = "tank/kubernetes";
                    isDefault = true;
                    server = "172.16.30.53";
                    nameTemplate = "{{ .PVCNamespace }}-{{ .PVCName }}";
                    adoptExisting = "true";
                    reclaimPolicy = "Retain";
                    deleteStrategy = "retain";
                  }
                ];
              };
            };
            openbao = {
              repo = "oci://ghcr.io/openbao/charts/openbao";
              version = "0.29.5";
              hash = "sha256-5n9e6WA7/oXPmSPQH7uq7V3FfRgA+V4VSvfyFU8F2q4=";
              targetNamespace = "openbao";
              createNamespace = true;
              values = {
                injector.enabled = false;
                server = {
                  annotations = {
                    "prometheus.io/scrape" = "true";
                    "prometheus.io/port" = "8200";
                    "prometheus.io/path" = "/v1/sys/metrics";
                  };
                  ha = {
                    enabled = true;
                    replicas = 1;
                    raft.enabled = true;
                    raft.setNodeId = true;
                    raft.config = ''
                      ui = true

                      listener "tcp" {
                        tls_disable = 1
                        address = "[::]:8200"
                        cluster_address = "[::]:8201"
                        telemetry {
                          unauthenticated_metrics_access = "true"
                        }
                      }

                      storage "raft" {
                        path = "/openbao/data"
                      }

                      seal "static" {
                        current_key_id = "20260924"
                        current_key = "file:///openbao/seal/key"
                      }

                      service_registration "kubernetes" {}

                      telemetry {
                        prometheus_retention_time = "24h"
                        disable_hostname = true
                      }

                      initialize "kubernetes-auth" {
                        request "enable-kubernetes-auth" {
                          operation = "update"
                          path = "sys/auth/kubernetes"
                          data = {
                            type = "kubernetes"
                          }
                        }
                        request "configure-kubernetes-auth" {
                          operation = "update"
                          path = "auth/kubernetes/config"
                          data = {
                            kubernetes_host = "https://kubernetes.default.svc:443"
                          }
                        }
                      }

                      initialize "vault-config-operator" {
                        request "write-policy" {
                          operation = "update"
                          path = "sys/policies/acl/vault-config-operator"
                          data = {
                            policy = "path \"*\" { capabilities = [\"create\", \"read\", \"update\", \"delete\", \"list\", \"sudo\"] }"
                          }
                        }
                        request "write-role" {
                          operation = "update"
                          path = "auth/kubernetes/role/vault-config-operator"
                          data = {
                            bound_service_account_names = "vault-config-operator"
                            bound_service_account_namespaces = "openbao"
                            policies = "vault-config-operator"
                            ttl = "1m"
                          }
                        }
                      }
                    '';
                  };
                  volumes = [
                    {
                      name = "seal-key";
                      secret.secretName = "openbao-seal-key";
                    }
                  ];
                  volumeMounts = [
                    {
                      name = "seal-key";
                      mountPath = "/openbao/seal";
                      readOnly = true;
                    }
                  ];
                  resources = {
                    requests = {
                      cpu = "100m";
                      memory = "256Mi";
                    };
                    limits.memory = "512Mi";
                  };
                  gateway.httpRoute = {
                    enabled = true;
                    hosts = ["openbao.internal.k8s.burned.host"];
                    parentRefs = [
                      {
                        name = "burned-gateway";
                        namespace = "gateway-system";
                        sectionName = "internal-https";
                      }
                    ];
                  };
                };
              };
            };
            argo-cd = {
              repo = "https://argoproj.github.io/argo-helm";
              name = "argo-cd";
              version = "10.9.2";
              hash = "sha256-lwztNGoN3D5HWn/3gOm5wv3rwH2aNn0u22709Jgywko=";
              targetNamespace = "argocd";
              createNamespace = true;
              values = {
                global.domain = "argocd.internal.k8s.burned.host";
                dex.enabled = false;
                configs.params."server.insecure" = true;
                configs.params."controller.diff.server.side" = "true";
                # Login through Keycloak; the client secret is generated in OpenBao (platform/keycloak.yaml).
                configs.cm."oidc.config" = ''
                  name: Keycloak
                  issuer: https://auth.burned.host/realms/homelab
                  clientID: argocd
                  clientSecret: $argocd-oidc-client-secret:client_secret
                  requestedScopes: ["openid", "profile", "email"]
                  enablePKCEAuthentication: true
                '';
                configs.rbac."policy.csv" = "g, admin, role:admin";
                configs.rbac.scopes = "[groups]";
                configs.cm = {
                  "resource.customizations.health.argoproj.io_Application" = ''
                    hs = {}
                    hs.status = "Progressing"
                    hs.message = ""
                    if obj.status ~= nil and obj.status.health ~= nil then
                      hs.status = obj.status.health.status
                      if obj.status.health.message ~= nil then
                        hs.message = obj.status.health.message
                      end
                    end
                    return hs
                  '';
                  "resource.customizations.health.postgresql.cnpg.io_Cluster" = ''
                    hs = { status = "Progressing", message = "Waiting for the cluster to be ready" }
                    if obj.status ~= nil and obj.status.conditions ~= nil then
                      for _, c in ipairs(obj.status.conditions) do
                        if c.type == "Ready" and c.status == "True" then
                          hs.status = "Healthy"
                          hs.message = c.message
                        end
                      end
                    end
                    return hs
                  '';
                  "resource.customizations.health.k8s.keycloak.org_Keycloak" = ''
                    hs = { status = "Progressing", message = "Waiting for Keycloak to be ready" }
                    if obj.status ~= nil and obj.status.conditions ~= nil then
                      for _, c in ipairs(obj.status.conditions) do
                        if c.type == "Ready" and c.status == "True" then
                          hs.status = "Healthy"
                          hs.message = c.message
                        end
                      end
                    end
                    return hs
                  '';
                  "resource.customizations.health.k8s.keycloak.org_KeycloakRealmImport" = ''
                    hs = { status = "Progressing", message = "Waiting for the realm import" }
                    if obj.status ~= nil and obj.status.conditions ~= nil then
                      for _, c in ipairs(obj.status.conditions) do
                        if c.type == "HasErrors" and c.status == "True" then
                          return { status = "Degraded", message = c.message }
                        end
                        if c.type == "Done" and c.status == "True" then
                          hs.status = "Healthy"
                          hs.message = c.message
                        end
                      end
                    end
                    return hs
                  '';
                };
                server.httproute = {
                  enabled = true;
                  hostnames = ["argocd.internal.k8s.burned.host"];
                  parentRefs = [
                    {
                      name = "burned-gateway";
                      namespace = "gateway-system";
                      sectionName = "internal-https";
                    }
                  ];
                };
              };
            };
          };
        };
      };
    };

    nixosConfigurations = {
      k8s-node-1 = withSystem "x86_64-linux" (
        {system, ...}:
          inputs.nixpkgs.lib.nixosSystem {
            modules = [
              self.diskoConfigurations.kubernetes-node-disk
              self.nixosModules.common-nix-module
              self.nixosModules.common-kubernetes-module
              self.nixosModules.hyperv-vm
              self.nixosModules.artur
              {
                networking.hostName = "k8s-node-1";
                age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBgayw+LEcOM0N62lRmY67rwsut5AlQzH7s30qi1/uKE";
                nixpkgs.hostPlatform = system;
                services.k3s.clusterInit = true;
              }
            ];
          }
      );

      k8s-node-2 = withSystem "x86_64-linux" (
        {system, ...}:
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
                nixpkgs.hostPlatform = system;
              }
            ];
          }
      );

      k8s-node-3 = withSystem "x86_64-linux" (
        {system, ...}:
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
                nixpkgs.hostPlatform = system;
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

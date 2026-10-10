{inputs, ...}: {
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
          revision=$(git rev-parse HEAD)
          staging=$(mktemp -d)
          trap 'rm -rf "$staging"' EXIT
          cp -r . "$staging"
          cd "$staging"
          oras push --username bakedchicken --password-stdin \
            --annotation "org.opencontainers.image.source=https://github.com/bakedchicken/nixos-config" \
            --annotation "org.opencontainers.image.revision=$revision" \
            --annotation "host.burned.dirty=$dirty" \
            ghcr.io/bakedchicken/platform:latest . < "$token"
        '';
      });
    };
  };

  flake.nixosModules = {
    vm-disk = {lib, ...}: {
      imports = [
        inputs.disko.nixosModules.default
      ];

      disko.devices.disk.main = {
        device = lib.mkDefault "/dev/sda";
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

    raspberry-pi-3 = {modulesPath, ...}: {
      imports = [
        "${modulesPath}/profiles/minimal.nix"
        inputs.nixos-raspberry-pi-uefi.nixosModules.default
      ];

      hardware.pi3.uefi.enable = true;
      fileSystems."/".fsType = "btrfs";

      zramSwap = {
        enable = true;
        memoryPercent = 50;
      };

      services.journald.settings.Journal = {
        Storage = "volatile";
        RuntimeMaxUse = "16M";
      };
    };

    gateway-api-crds = {
      config,
      lib,
      pkgs,
      ...
    }: {
      services.k3s.manifests = lib.mkIf (config.kubernetes.role == "server") {
        gateway-api.source = pkgs.fetchurl {
          url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/experimental-install.yaml";
          hash = "sha256-8NXCsL7yudgLprqQnl5dveCABjhDdgg1P0Gm69OvzZ8=";
        };
      };
    };

    snapshot-crds = {
      config,
      lib,
      pkgs,
      ...
    }: {
      services.k3s.manifests = lib.mkIf (config.kubernetes.role == "server") {
        volume-snapshot-crds.source = let
          src = pkgs.fetchFromGitHub {
            owner = "kubernetes-csi";
            repo = "external-snapshotter";
            rev = "v8.6.0";
            hash = "sha256-9WSflI44XhecRqBWGKDfeMMHqOBwyInX9w2qMLDPylA=";
          };
        in
          pkgs.runCommand "volume-snapshot-crds.yaml" {nativeBuildInputs = [pkgs.kubectl];} ''
            kubectl kustomize -o $out ${src}/client/config/crd
            echo "---" >> $out
            kubectl kustomize ${src}/deploy/kubernetes/snapshot-controller >> $out
          '';
      };
    };

    flannel = {
      config,
      lib,
      ...
    }: {
      services.k3s.extraFlags = lib.mkIf (config.kubernetes.role == "server") [
        "--flannel-ipv6-masq"
      ];
    };

    # CNI, kube-proxy replacement, Gateway API implementation, LoadBalancer IPs, Hubble
    cilium = {
      config,
      lib,
      pkgs,
      ...
    }: let
      cluster = config.kubernetes.cluster;
    in {
      services.k3s = lib.mkIf (config.kubernetes.role == "server") {
        extraFlags = [
          "--flannel-backend=none"
          "--disable-network-policy"
          "--disable-kube-proxy"
        ];
        manifests = {
          cluster-ip-pool.content = {
            apiVersion = "cilium.io/v2";
            kind = "CiliumLoadBalancerIPPool";
            metadata.name = "only-pool";
            spec.blocks = cluster.loadBalancerPool;
          };
        };
        autoDeployCharts.cilium = {
          repo = "oci://quay.io/cilium/charts/cilium";
          version = "1.21.0-pre.2";
          hash = "sha256-t09VSVgfyxKG9N+6Ip8zGwd9U+MRH0vIM9uPUI0UhR4=";
          targetNamespace = "kube-system";
          extraFieldDefinitions = {
            spec.bootstrap = true;
          };
          values = {
            # k3s's local API load balancer, present on every node: no node address needed
            k8sServiceHost = "127.0.0.1";
            k8sServicePort = "6444";
            ipv4.enabled = lib.elem "ipv4" cluster.families;
            ipv6.enabled = lib.elem "ipv6" cluster.families;
            routingMode = "native";
            autoDirectNodeRoutes = true;
            ipv4NativeRoutingCIDR = cluster.clusterCidr.ipv4;
            ipv6NativeRoutingCIDR = cluster.clusterCidr.ipv6;
            ipam.mode = "cluster-pool";
            ipam.operator.clusterPoolIPv4PodCIDRList = [cluster.clusterCidr.ipv4];
            ipam.operator.clusterPoolIPv4MaskSize = 24;
            ipam.operator.clusterPoolIPv6PodCIDRList = [cluster.clusterCidr.ipv6];
            ipam.operator.clusterPoolIPv6MaskSize = 64;
            extraConfig.enable-ipv6-ndp = "true";
            extraConfig.ipv6-mcast-device = "eth0";
            kubeProxyReplacement = true;
            cni.exclusive = false;
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
              hostnames = ["hubble.${cluster.internalDomain}"];
            };
          };
        };
      };
    };

    kube-vip = {
      config,
      lib,
      ...
    }: {
      services.k3s.manifests = lib.mkIf (config.kubernetes.role == "server") {
        kube-vip.source = ./infra/kube-vip.yaml;
      };
    };

    truenas-csi = {
      config,
      lib,
      pkgs,
      ...
    }: let
      cluster = config.kubernetes.cluster;
      isServer = config.kubernetes.role == "server";
    in {
      services.openiscsi = {
        enable = true;
        name = "iqn.2026-09.host.burned:${config.networking.hostName}";
      };

      systemd.tmpfiles.rules = ["L+ /usr/sbin/iscsiadm - - - - ${config.services.openiscsi.package}/bin/iscsiadm"];

      age.secrets = lib.mkIf isServer {
        truenas-api-key.rekeyFile = ./secrets/truenas-api-key.age;
      };

      systemd.services.k3s.restartTriggers = lib.mkIf isServer [
        config.age.secrets.truenas-api-key.file
      ];

      services.k3s = lib.mkIf isServer {
        disable = [
          "local-storage"
        ];
        manifests.truenas-api-key.source = config.age.secrets.truenas-api-key.path;
        autoDeployCharts.tns-csi = {
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
                name = "tns-csi-iscsi";
                protocol = "iscsi";
                pool = "tank";
                parentDataset = cluster.storage.parentDataset;
                isDefault = true;
                server = "172.16.33.53";
                nameTemplate = "{{ .PVCNamespace }}-{{ .PVCName }}";
                adoptExisting = "true";
                reclaimPolicy = "Retain";
                deleteStrategy = "retain";
              }
              {
                enabled = true;
                name = "tns-csi-nfs";
                protocol = "nfs";
                pool = "tank";
                parentDataset = cluster.storage.parentDataset;
                server = "172.16.33.53";
                nameTemplate = "{{ .PVCNamespace }}-{{ .PVCName }}";
                adoptExisting = "true";
                reclaimPolicy = "Retain";
                deleteStrategy = "retain";
              }
            ];
          };
        };
      };
    };

    openbao = {
      config,
      lib,
      ...
    }: let
      cluster = config.kubernetes.cluster;
      isServer = config.kubernetes.role == "server";
    in {
      age.secrets = lib.mkIf isServer {
        openbao-seal-key.rekeyFile = ./secrets/openbao-seal-key.age;
      };

      systemd.services.k3s.restartTriggers = lib.mkIf isServer [
        config.age.secrets.openbao-seal-key.file
      ];

      services.k3s = lib.mkIf isServer {
        manifests.openbao-seal-key.source = config.age.secrets.openbao-seal-key.path;
        autoDeployCharts.openbao = {
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
                hosts = ["openbao.${cluster.internalDomain}"];
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

    argocd = {
      config,
      lib,
      ...
    }: let
      cluster = config.kubernetes.cluster;
      isServer = config.kubernetes.role == "server";
    in {
      age.secrets = lib.mkIf isServer {
        argocd-ghcr-creds.rekeyFile = ./secrets/argocd-ghcr-credentials.age;
        cloudflare-api-token.rekeyFile = ./secrets/cloudflare-api-token.age;
        keycloak-admin-password.rekeyFile = ./secrets/keycloak-admin-password.age;
        argocd-cluster-edge.rekeyFile = ./secrets/argocd-cluster-edge.age;
      };

      systemd.services.k3s.restartTriggers = lib.mkIf isServer [
        config.age.secrets.argocd-ghcr-creds.file
        config.age.secrets.cloudflare-api-token.file
        config.age.secrets.keycloak-admin-password.file
        config.age.secrets.argocd-cluster-edge.file
      ];

      services.k3s = lib.mkIf isServer {
        manifests = {
          argocd-ghcr-creds.source = config.age.secrets.argocd-ghcr-creds.path;
          cloudflare-api-token.source = config.age.secrets.cloudflare-api-token.path;
          keycloak-admin-password.source = config.age.secrets.keycloak-admin-password.path;
          argocd-cluster-edge.source = config.age.secrets.argocd-cluster-edge.path;
          argocd-bootstrap.source = ./infra/argocd-bootstrap.yaml;
        };
        autoDeployCharts.argo-cd = {
          repo = "https://argoproj.github.io/argo-helm";
          name = "argo-cd";
          version = "10.9.2";
          hash = "sha256-lwztNGoN3D5HWn/3gOm5wv3rwH2aNn0u22709Jgywko=";
          targetNamespace = "argocd";
          createNamespace = true;
          values = {
            global.domain = "argocd.${cluster.internalDomain}";
            dex.enabled = false;
            configs.params."server.insecure" = true;
            configs.params."controller.diff.server.side" = "true";
            configs.cm."admin.enabled" = false;
            configs.cm."oidc.config" = ''
              name: Keycloak
              issuer: https://auth.${cluster.domain}/realms/burned
              clientID: argocd
              clientSecret: $argocd-oidc-client-secret:client_secret
              requestedScopes: ["openid", "profile", "email"]
              enablePKCEAuthentication: true
            '';
            configs.rbac."policy.csv" = "g, admin, role:admin\ng, readonly, role:readonly";
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
              hostnames = ["argocd.${cluster.internalDomain}"];
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

    argocd-spoke = {
      config,
      lib,
      ...
    }: let
      ca = config.kubernetes.cluster.ca;
      tls = "/var/lib/rancher/k3s/server/tls";
      isServer = config.kubernetes.role == "server";
    in {
      age.secrets = lib.mkIf isServer {
        k3s-server-ca-crt = {
          rekeyFile = ca.cert;
          path = "${tls}/server-ca.crt";
        };
        k3s-server-ca-key = {
          rekeyFile = ca.key;
          path = "${tls}/server-ca.key";
        };
        k3s-client-ca-crt = {
          rekeyFile = ca.cert;
          path = "${tls}/client-ca.crt";
        };
        k3s-client-ca-key = {
          rekeyFile = ca.key;
          path = "${tls}/client-ca.key";
        };
      };

      services.k3s.manifests = lib.mkIf isServer {
        argocd-cluster-admin.content = {
          apiVersion = "rbac.authorization.k8s.io/v1";
          kind = "ClusterRoleBinding";
          metadata.name = "argocd-cluster-admin";
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = "cluster-admin";
          };
          subjects = [
            {
              apiGroup = "rbac.authorization.k8s.io";
              kind = "User";
              name = "argocd";
            }
          ];
        };
      };
    };

    mktxp = {
      config,
      lib,
      ...
    }: let
      isServer = config.kubernetes.role == "server";
    in {
      age.secrets = lib.mkIf isServer {
        mktxp-credentials.rekeyFile = ./secrets/mktxp-credentials.age;
      };

      systemd.services.k3s.restartTriggers = lib.mkIf isServer [
        config.age.secrets.mktxp-credentials.file
      ];

      services.k3s.manifests = lib.mkIf isServer {
        mktxp-credentials.source = config.age.secrets.mktxp-credentials.path;
      };
    };
  };
}

{
  inputs,
  config,
  ...
}: let
  clusters = config.kubernetes.clusters;
in {
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
    # storage-station's side of the clusters' storage: the LIO iSCSI target and the csi user democratic-csi logs
    # in as, allowed to manage each cluster's dataset and nothing else
    storage-server = {
      config,
      lib,
      pkgs,
      ...
    }: {
      boot.kernelModules = [
        "configfs"
        "target_core_mod"
        "iscsi_target_mod"
      ];
      environment.systemPackages = [pkgs.targetcli-fb];
      # targetcli saves the target configuration to /etc/target; /etc is read-only, so that points into /var/lib
      environment.etc."target".source = "/var/lib/target";

      systemd.services.iscsi-target = {
        description = "Restore the LIO iSCSI target configuration";
        after = [
          "network.target"
          "local-fs.target"
        ];
        requires = ["sys-kernel-config.mount"];
        wantedBy = ["multi-user.target"];
        unitConfig.ConditionPathExists = "/var/lib/target/saveconfig.json";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${lib.getExe pkgs.python3Packages.rtslib-fb} restore";
          ExecStop = "${lib.getExe pkgs.python3Packages.rtslib-fb} clear";
        };
      };

      security.sudo.extraRules = [
        {
          users = ["csi"];
          commands = [
            {
              command = "/run/current-system/sw/bin/targetcli";
              options = ["NOPASSWD"];
            }
          ];
        }
      ];

      systemd.services.csi-zfs-delegation = {
        description = "Delegate the clusters' datasets to the csi user";
        after = ["zfs-import.target"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = [
            "${config.boot.zfs.package}/bin/zfs allow -u csi create,destroy,mount,snapshot,clone,promote,rename,send,receive,hold,release,userprop,volsize,volblocksize,compression,refreservation,reservation,refquota,quota,snapdev ${clusters.main.storage.dataset}"
            "${config.boot.zfs.package}/bin/zfs allow -u csi create,destroy,mount,snapshot,clone,promote,rename,send,receive,hold,release,userprop,volsize,volblocksize,compression,refreservation,reservation,refquota,quota,snapdev ${clusters.edge.storage.dataset}"
          ];
        };
      };

      # The private key is in each cluster's democratic-csi driver config
      users.users.csi = {
        isSystemUser = true;
        group = "csi";
        shell = pkgs.bash;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIzRhR3bAOQmT03QUu0pOgNq/xeq4Kgtoqu992QCOcGv democratic-csi@clusters"
        ];
      };
      users.groups.csi = {};
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
          version = "1.21.0-pre.3";
          hash = "sha256-MyFvvjGa8CPcnoqvksMfupRa3IVvv6TPCd6F8JAvQbE=";
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
            # No L7 proxy of Cilium's own: the gateway and the mesh are Istio's
            l7Proxy = false;
            envoy.enabled = false;
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
            serverTelemetry.grafanaDashboard = {
              enabled = true;
              extraAnnotations.grafana_folder = "OpenBao";
            };
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
      pkgs,
      ...
    }: let
      cluster = config.kubernetes.cluster;
      isServer = config.kubernetes.role == "server";
    in {
      age.secrets = lib.mkIf isServer {
        cloudflare-api-token.rekeyFile = ./secrets/cloudflare-api-token.age;
        keycloak-admin-password.rekeyFile = ./secrets/keycloak-admin-password.age;
        argocd-cluster-edge.rekeyFile = ./secrets/argocd-cluster-edge.age;
      };

      systemd.services.k3s.restartTriggers = lib.mkIf isServer [
        config.age.secrets.cloudflare-api-token.file
        config.age.secrets.keycloak-admin-password.file
        config.age.secrets.argocd-cluster-edge.file
      ];

      systemd.services.argocd-ghcr-creds = lib.mkIf isServer {
        description = "Render the Argo CD ghcr.io repository credentials";
        wantedBy = ["k3s.service"];
        before = ["k3s.service"];
        restartTriggers = [config.age.secrets.ghcr-token.file];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          RuntimeDirectory = "argocd-ghcr-creds";
          RuntimeDirectoryMode = "0700";
          ExecStart = [
            "${pkgs.coreutils}/bin/install -m 0600 ${(pkgs.formats.json {}).generate "argocd-ghcr-creds.yaml" {
              apiVersion = "v1";
              kind = "Secret";
              metadata = {
                name = "ghcr-bakedchicken";
                namespace = "argocd";
                labels."argocd.argoproj.io/secret-type" = "repo-creds";
              };
              stringData = {
                type = "oci";
                url = "oci://ghcr.io/bakedchicken";
                username = "bakedchicken";
                password = "@token@";
              };
            }} /run/argocd-ghcr-creds/argocd-ghcr-creds.yaml"
            "${pkgs.replace-secret}/bin/replace-secret @token@ ${config.age.secrets.ghcr-token.path} /run/argocd-ghcr-creds/argocd-ghcr-creds.yaml"
          ];
        };
      };

      services.k3s = lib.mkIf isServer {
        manifests = {
          argocd-ghcr-creds.source = "/run/argocd-ghcr-creds/argocd-ghcr-creds.yaml";
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

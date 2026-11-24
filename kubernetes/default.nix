{
  self,
  inputs,
  lib,
  config,
  flake-parts-lib,
  ...
}: let
  inherit (lib) mkOption types;
  cfg = config.kubernetes;
  democraticCsi = {
    repo = "https://democratic-csi.github.io/charts/";
    name = "democratic-csi";
    version = "0.15.1";
    hash = "sha256-PYfhKc6kbUnYEOnlCFth0GwBoxO8+SFg49EGrcMEJu0=";
    driverImageTag = "latest@sha256:944d0e65077efbd9c1fdf23997eec8fac4b4bfb7c3de400f63e33a0a849c5ced";
  };
in {
  imports = [
    ./addons.nix
  ];

  options.flake = flake-parts-lib.mkSubmoduleOptions {
    deploy.nodes = mkOption {
      type = types.lazyAttrsOf types.raw;
      default = {};
    };
  };

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
          description = "Server that initialises the cluster; every other node joins it at its FQDN";
        };
        embeddedEtcd = mkOption {
          type = types.bool;
          description = "Embedded etcd instead of SQLite; needed for more than one server";
        };
        clusterCidr = mkOption {
          type = types.str;
          default = "fd42::/56";
          description = "Pod network. Clusters are IPv6-only; changing it means reinstalling the cluster";
        };
        serviceCidr = mkOption {
          type = types.str;
          default = "fd43::/112";
          description = "Service network";
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
        storage.dataset = mkOption {
          type = types.str;
          description = "Dataset on storage-station holding this cluster's volumes (zvols named <namespace>-<pvc>); never shared between clusters";
        };
        storage.postgresDataset = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Dataset on storage-station holding this cluster's Postgres volumes (the postgres-storage add-on), outside storage.dataset so sanoid leaves them alone";
        };
        storage.csiDriverConfig = mkOption {
          type = types.path;
          description = "agenix-rekey source of democratic-csi's driver config (a Secret manifest): the csi user's SSH key and this cluster's dataset on storage-station, never shared between clusters";
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
              system = mkOption {type = types.enum ["x86_64-linux"];};
              hostPubkey = mkOption {type = types.str;};
              modules = mkOption {
                type = types.listOf types.deferredModule;
                default = [];
                description = "NixOS modules for this machine only";
              };
            };
          });
        };
      };
    });
  };

  config._module.args.democraticCsi = democraticCsi;

  config.flake = {
    nixosModules.kubernetes-node = {
      config,
      lib,
      pkgs,
      ...
    }: let
      cluster = config.kubernetes.cluster;
      isInit = config.networking.hostName == cluster.init;
    in {
      options.kubernetes = {
        clusterName = lib.mkOption {type = lib.types.str;};
        cluster = lib.mkOption {type = lib.types.raw;};
      };

      options.services.k3s.manifests = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
          config.target = lib.mkOverride 900 "nixos/${name}.yaml";
        }));
      };

      config = {
        systemd.tmpfiles.rules = [
          "d /var/lib/rancher/etc 0755 root root - -"
          "d /var/lib/rancher/cni 0755 root root - -"
          "d /var/lib/iscsi/nodes 0700 root root - -"
          "d /var/lib/iscsi/send_targets 0700 root root - -"
          "d /var/lib/iscsi/ifaces 0700 root root - -"
          "L+ /usr/sbin/iscsiadm - - - - ${config.services.openiscsi.package}/bin/iscsiadm"
          "R /var/lib/rancher/k3s/server/manifests/nixos - - - - -"
        ];

        environment.etc = {
          "rancher".source = "/var/lib/rancher/etc";
          "cni".source = "/var/lib/rancher/cni";
          "iscsi/iscsid.conf".source = "/var/lib/iscsi/iscsid.conf";
          "iscsi/nodes".source = "/var/lib/iscsi/nodes";
          "iscsi/send_targets".source = "/var/lib/iscsi/send_targets";
          "iscsi/ifaces".source = "/var/lib/iscsi/ifaces";
        };
        environment.persistence."/persist".directories = [
          "/var/lib/rancher"
          "/var/lib/kubelet"
          "/var/lib/iscsi"
          "/opt/cni/bin"
        ];

        systemd.network.config.networkConfig = {
          ManageForeignRoutes = false;
          ManageForeignRoutingPolicyRules = false;
        };

        networking = {
          tempAddresses = "disabled";
          firewall = {
            checkReversePath = false;
            allowedTCPPorts = [
              6443
              4240
              4244
              9963
              9100
              10250
            ];
          };
        };

        boot.kernel.sysctl."kernel.panic" = 10;

        environment.variables = {
          KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
        };

        environment.systemPackages = with pkgs; [
          k9s
          kubectl
          kubectl-cnpg
          kubernetes-helm
        ];

        services.openiscsi = {
          enable = true;
          name = "iqn.2026-09.host.burned:${config.networking.hostName}";
          extraConfig = "node.session.timeo.replacement_timeout = 1800";
        };

        age.secrets = {
          join-token = {
            rekeyFile = cluster.tokenFile;
            generator.script = "alnum";
          };
          ghcr-token.rekeyFile = ./secrets/ghcr-token.age;
          democratic-csi-config.rekeyFile = cluster.storage.csiDriverConfig;
        };

        systemd.services.ghcr-registries = {
          description = "Render k3s registries.yaml with the ghcr.io token";
          wantedBy = ["k3s.service"];
          before = ["k3s.service"];
          after = ["agenix-install-secrets.service"];
          restartTriggers = [config.age.secrets.ghcr-token.file];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            RuntimeDirectory = "ghcr-registries";
            RuntimeDirectoryMode = "0700";
            ExecStart = [
              "${pkgs.coreutils}/bin/install -m 0600 ${(pkgs.formats.yaml {}).generate "registries.yaml" {
                configs."ghcr.io".auth = {
                  username = "bakedchicken";
                  password = "@token@";
                };
              }} /run/ghcr-registries/registries.yaml"
              "${pkgs.replace-secret}/bin/replace-secret @token@ ${config.age.secrets.ghcr-token.path} /run/ghcr-registries/registries.yaml"
            ];
          };
        };

        systemd.services.k3s.after = ["agenix-install-secrets.service"];
        systemd.services.k3s.restartTriggers =
          [config.age.secrets.ghcr-token.file]
          ++ config.services.k3s.images
          ++ [config.age.secrets.democratic-csi-config.file];

        services.k3s = {
          enable = true;
          tokenFile = config.age.secrets.join-token.path;
          clusterInit = isInit && cluster.embeddedEtcd;
          serverAddr = lib.mkIf (!isInit) "https://${cluster.init}.${config.networking.domain}:6443";
          disable = ["local-storage"];
          extraFlags = [
            "--private-registry=/run/ghcr-registries/registries.yaml"
            "--write-kubeconfig-mode=0640"
            "--write-kubeconfig-group=wheel"
            "--tls-san=${config.networking.fqdn}"
            "--tls-san=${cluster.domain}"
            "--cluster-cidr=${cluster.clusterCidr}"
            "--service-cidr=${cluster.serviceCidr}"
          ];

          manifests = lib.mkMerge [
            (lib.mapAttrs (name: chart: {source = chart.source;}) config.services.k3s.autoDeployCharts)
            {
              gateway-api.source = pkgs.fetchurl {
                url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.3/experimental-install.yaml";
                hash = "sha256-cvVJ/1dBbi4QhcW+Fxj1+GEIqnWsObS8J8HHrvFJcSc=";
              };
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
              democratic-csi-config.source = config.age.secrets.democratic-csi-config.path;
            }
          ];

          autoDeployCharts.democratic-csi = {
            inherit (democraticCsi) repo name version hash;
            targetNamespace = "kube-system";
            extraFieldDefinitions = {
              spec.bootstrap = true;
            };
            values = {
              csiDriver.name = "org.democratic-csi.iscsi";
              driver = {
                existingConfigSecret = "democratic-csi-driver-config";
                config.driver = "zfs-generic-iscsi";
              };
              controller.driver.image.tag = democraticCsi.driverImageTag;
              node.driver.image.tag = democraticCsi.driverImageTag;
              storageClasses = [
                {
                  name = "iscsi";
                  defaultClass = true;
                  reclaimPolicy = "Retain";
                  volumeBindingMode = "Immediate";
                  allowVolumeExpansion = true;
                  parameters.fsType = "ext4";
                }
              ];
              volumeSnapshotClasses = [
                {
                  name = "iscsi-snapshot";
                  parameters.detachedSnapshots = "false";
                }
              ];
            };
          };
        };
      };
    };

    nixosConfigurations = lib.concatMapAttrs (clusterName: cluster:
      lib.mapAttrs (nodeName: node:
        inputs.nixpkgs.lib.nixosSystem {
          modules =
            [
              self.nixosModules.base
              self.nixosModules.kubernetes-node
              self.nixosModules.artur
              {
                networking.hostName = nodeName;
                nixpkgs.hostPlatform = node.system;
                age.rekey.hostPubkey = node.hostPubkey;
                kubernetes = {inherit clusterName cluster;};
              }
            ]
            ++ node.modules
            ++ cluster.modules;
        })
      cluster.nodes)
    cfg.clusters;

    deploy.nodes = lib.concatMapAttrs (clusterName: cluster:
      lib.mapAttrs (nodeName: node: {
        hostname = self.nixosConfigurations.${nodeName}.config.networking.fqdn;
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

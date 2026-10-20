# The clusters: their options, what every node runs, and the generated nixosConfigurations and deploy targets. The
# clusters themselves are defined in flake.nix, the add-ons in addons.nix.
{
  self,
  inputs,
  lib,
  config,
  withSystem,
  flake-parts-lib,
  ...
}: let
  inherit (lib) mkOption types;
  cfg = config.kubernetes;
in {
  imports = [
    ./addons.nix
  ];

  # deploy-rs nodes come from here and from flake.nix, so they have to merge
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
          description = "Server that initialises the cluster; every other node joins it at <init>.local";
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
        storage.dataset = mkOption {
          type = types.str;
          description = "Dataset on storage-station holding this cluster's volumes (zvols named <namespace>-<pvc>); never shared between clusters";
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
              role = mkOption {type = types.enum ["server" "agent"];};
              system = mkOption {type = types.enum ["x86_64-linux" "aarch64-linux"];};
              hostPubkey = mkOption {type = types.str;};
              deploy = mkOption {
                type = types.bool;
                default = true;
                description = "Whether the node gets a deploy-rs target; false for a node built into another machine";
              };
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

  config.flake = {
    # k3s with what both clusters need: open-iscsi and democratic-csi against storage-station, the Gateway API and
    # volume snapshot CRDs, the ghcr.io pull credentials
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

      # Charts are declared as autoDeployCharts for their options, but written as manifests (nixos/<name>.yaml) so
      # a chart can be bootstrapped before the API server is up and removed with its manifest
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
        systemd.tmpfiles.rules =
          [
            "d /var/lib/rancher/etc 0755 root root - -"
            "d /var/lib/rancher/cni 0755 root root - -"
            "d /var/lib/iscsi/nodes 0700 root root - -"
            "d /var/lib/iscsi/send_targets 0700 root root - -"
            "d /var/lib/iscsi/ifaces 0700 root root - -"
            "L+ /usr/sbin/iscsiadm - - - - ${config.services.openiscsi.package}/bin/iscsiadm"
          ]
          ++ lib.optional isServer "R /var/lib/rancher/k3s/server/manifests/nixos - - - - -";

        # k3s, the CNI and iscsid write under /etc; /etc is read-only, so those paths point into persisted state
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
        ];

        # Cilium turns off reverse-path filtering on the pods' interfaces by writing a file into /etc/sysctl.d,
        # which a read-only /etc refuses; without it the kernel drops the pods' replies
        boot.kernel.sysctl."net.ipv4.conf.lxc*.rp_filter" = 0;

        networking = {
          usePredictableInterfaceNames = false;
          # The CNI's interfaces are outside NetworkManager's connection settings
          tempAddresses = "disabled";
          networkmanager.unmanaged = [
            "interface-name:lxc*"
            "interface-name:cilium*"
            "interface-name:flannel*"
            "interface-name:cni*"
            "interface-name:veth*"
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

        services.openiscsi = {
          enable = true;
          name = "iqn.2026-09.host.burned:${config.networking.hostName}";
        };

        age.secrets = lib.mkMerge [
          {
            join-token = {
              rekeyFile = cluster.tokenFile;
              generator.script = "alnum";
            };
            ghcr-token.rekeyFile = ./secrets/ghcr-token.age;
          }
          (lib.mkIf isServer {
            democratic-csi-config.rekeyFile = cluster.storage.csiDriverConfig;
          })
        ];

        systemd.services.ghcr-registries = {
          description = "Render k3s registries.yaml with the ghcr.io token";
          wantedBy = ["k3s.service"];
          before = ["k3s.service"];
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

        systemd.services.k3s.restartTriggers =
          [config.age.secrets.ghcr-token.file]
          ++ lib.optional isServer config.age.secrets.democratic-csi-config.file;

        services.k3s = {
          enable = true;
          role = config.kubernetes.role;
          tokenFile = config.age.secrets.join-token.path;
          clusterInit = isInit && lib.length (lib.filter (node: node.role == "server") (lib.attrValues cluster.nodes)) > 1;
          serverAddr = lib.mkIf (!isInit) "https://${cluster.init}.local:6443";
          disable = lib.mkIf isServer [
            "traefik"
            "servicelb"
            "local-storage"
          ];
          extraFlags = lib.mkMerge [
            ["--private-registry /run/ghcr-registries/registries.yaml"]
            (lib.mkIf isServer [
              "--write-kubeconfig-mode 0644"
              "--tls-san ${config.networking.hostName}.local"
              "--tls-san ${cluster.domain}"
              "--cluster-cidr=${lib.concatMapStringsSep "," (family: cluster.clusterCidr.${family}) cluster.families}"
              "--service-cidr=${lib.concatMapStringsSep "," (family: cluster.serviceCidr.${family}) cluster.families}"
            ])
          ];

          charts = lib.mapAttrs (name: chart: chart.package) config.services.k3s.autoDeployCharts;
          manifests = lib.mkMerge [
            (lib.mapAttrs (name: chart: {source = chart.source;}) config.services.k3s.autoDeployCharts)
            (lib.mkIf isServer {
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
            })
          ];

          # Volumes are zvols under the cluster's dataset on storage-station, exported over iSCSI; democratic-csi
          # logs in there as the csi user over SSH. Names stay <namespace>-<pvc>, so a reinstalled cluster re-adopts
          # them. Never declare a claim smaller than its zvol: the driver would shrink it.
          autoDeployCharts.democratic-csi = lib.mkIf isServer {
            repo = "https://democratic-csi.github.io/charts/";
            name = "democratic-csi";
            version = "0.15.1";
            hash = "sha256-PYfhKc6kbUnYEOnlCFth0GwBoxO8+SFg49EGrcMEJu0=";
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
              # The chart defaults to "latest"
              controller.driver.image.tag = "latest@sha256:944d0e65077efbd9c1fdf23997eec8fac4b4bfb7c3de400f63e33a0a849c5ced";
              node.driver.image.tag = "latest@sha256:944d0e65077efbd9c1fdf23997eec8fac4b4bfb7c3de400f63e33a0a849c5ced";
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
                  deletionPolicy = "Delete";
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
        withSystem node.system ({system, ...}:
          inputs.nixpkgs.lib.nixosSystem {
            modules =
              [
                self.nixosModules.base
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
      (lib.filterAttrs (nodeName: node: node.deploy) cluster.nodes))
    cfg.clusters;
  };
}

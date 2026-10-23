# storage-station's services: SMB shares, the media apps, the edge cluster's server container, the dashboard.
# The machine itself (board, boot, pools, network, users) is in flake.nix.
{
  config,
  lib,
  pkgs,
  ...
}: {
  services.samba = {
    enable = true;
    openFirewall = true;
    # A standalone server: no domain to join
    winbindd.enable = false;
    settings = {
      global = {
        "server min protocol" = "SMB3";
        "server multi channel support" = "yes";
        "ntlm auth" = "ntlmv2-only";
        "mangled names" = "no";
        "unix charset" = "UTF-8";
        "vfs objects" = "fruit streams_xattr";
        "fruit:metadata" = "stream";
        "fruit:model" = "MacSamba";
        "fruit:nfs_aces" = "no";
      };
      "3d-models" = {
        "path" = "/srv/3d-models";
        "read only" = "no";
        "valid users" = "@designers";
        "force group" = "designers";
        "create mask" = "0770";
        "directory mask" = "0770";
      };
      "time-machine" = {
        "path" = "/srv/time-machine";
        "read only" = "no";
        "valid users" = "artur";
        "create mask" = "0700";
        "directory mask" = "0700";
        "fruit:time machine" = "yes";
      };
    };
  };

  services.avahi.extraServiceFiles.smb = ''
    <?xml version="1.0" standalone="no"?>
    <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
    <service-group>
      <name replace-wildcards="yes">%h</name>
      <service>
        <type>_smb._tcp</type>
        <port>445</port>
      </service>
      <service>
        <type>_device-info._tcp</type>
        <port>0</port>
        <txt-record>model=MacSamba</txt-record>
      </service>
      <service>
        <type>_adisk._tcp</type>
        <port>9</port>
        <txt-record>sys=waMa=0,adVF=0x100</txt-record>
        <txt-record>dk0=adVN=time-machine,adVF=0x82</txt-record>
      </service>
    </service-group>
  '';

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  # The shares' and the media's datasets are nofail mounts (flake.nix); without them the services would write to
  # the empty directories on the tmpfs root
  systemd.services.samba-smbd.unitConfig.RequiresMountsFor = [
    "/srv/3d-models"
    "/srv/time-machine"
  ];
  systemd.services.radarr.unitConfig.RequiresMountsFor = ["/srv/media"];
  systemd.services.plex.unitConfig.RequiresMountsFor = ["/srv/media"];
  systemd.services.podman-sonarr.unitConfig.RequiresMountsFor = ["/srv/media"];

  # The media apps: NixOS services as the apps user, each with its state on its own dataset under tank/apps, the
  # media on /srv/media, listening on localhost behind nginx. nofail: a mount that hangs (ZFS under load) must
  # not fail local-fs.target, which would drop the machine into emergency mode
  fileSystems."/var/lib/radarr" = {
    device = "tank/apps/radarr";
    fsType = "zfs";
    options = ["nofail"];
  };
  services.radarr = {
    enable = true;
    user = "apps";
    group = "apps";
    dataDir = "/var/lib/radarr";
    settings.server.bindaddress = "127.0.0.1";
  };
  # The media is shared with the other apps through the apps group
  systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";

  # Prowlarr's module runs it as a dynamic user, whose state lives under /var/lib/private
  fileSystems."/var/lib/private/prowlarr" = {
    device = "tank/apps/prowlarr";
    fsType = "zfs";
    options = ["nofail"];
  };
  services.prowlarr = {
    enable = true;
    settings.server.bindaddress = "127.0.0.1";
  };
  services.flaresolverr.enable = true;
  fileSystems."/var/lib/sonarr" = {
    device = "tank/apps/sonarr";
    fsType = "zfs";
    options = ["nofail"];
  };

  # The dataset keeps the layout Plex's container used: Library/Application Support/Plex Media Server
  fileSystems."/var/lib/plex" = {
    device = "tank/apps/plex";
    fsType = "zfs";
    options = ["nofail"];
  };
  # Plex is unfree
  nixpkgs.config.allowUnfree = true;
  services.plex = {
    enable = true;
    user = "apps";
    group = "apps";
    dataDir = "/var/lib/plex/Library/Application Support";
    openFirewall = true;
  };

  # No podman healthcheck: its timer fails while the app is still starting, which fails every
  # switch-to-configuration; Glance watches the app instead
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.containers = {
    # Sonarr stays a container until nixpkgs ships Sonarr 5 (its database is on the v5 schema). On the host's
    # network, so it talks to the other apps on localhost like they do.
    sonarr = {
      image = "ghcr.io/home-operations/sonarr:5.0.0.2569@sha256:b699df6b4b10e71ce23fb6fd8944653171f49164f79020cb0ea09e46b51b0517";
      user = "568:568";
      volumes = [
        "/var/lib/sonarr:/config"
        "/srv/media:/srv/media"
      ];
      environment = {
        TZ = "Europe/Vienna";
        UMASK = "002";
        SONARR__SERVER__BINDADDRESS = "127.0.0.1";
        SONARR__APP__INSTANCENAME = "Sonarr";
        SONARR__UPDATE__BRANCH = "develop";
      };
      extraOptions = [
        "--network=host"
        "--group-add=568"
        "--no-healthcheck"
      ];
    };
  };

  # qBittorrent in its own network: a NixOS container whose eth0 is a port of br0, so it has its own address on
  # the home network (its MAC is derived from the container name; the router routes that address through the
  # tunnel to Yekaterinburg). The qbt link is for the web UI only, which nginx proxies on the host. IPv4 only:
  # an IPv6 address would leave through the router's NAT66 instead.
  fileSystems."/var/lib/qbittorrent" = {
    device = "tank/apps/qbittorrent";
    fsType = "zfs";
    options = ["nofail"];
  };
  containers.qbittorrent = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";
    extraVeths.qbt = {
      hostAddress = "10.233.1.1";
      localAddress = "10.233.1.2";
    };
    bindMounts = {
      "/var/lib/qbittorrent".isReadOnly = false;
      "/srv/media".isReadOnly = false;
    };
    config = {
      networking.useHostResolvConf = false;
      networking.enableIPv6 = false;
      networking.interfaces.eth0.useDHCP = true;
      networking.firewall.interfaces.eth0.allowedTCPPorts = [51413];
      networking.firewall.interfaces.eth0.allowedUDPPorts = [51413];
      networking.firewall.interfaces.qbt.allowedTCPPorts = [8080];

      users.users.apps = {
        uid = 568;
        group = "apps";
        isSystemUser = true;
      };
      users.groups.apps.gid = 568;

      services.qbittorrent = {
        enable = true;
        user = "apps";
        group = "apps";
        profileDir = "/var/lib/qbittorrent";
        torrentingPort = 51413;
      };
      systemd.services.qbittorrent.serviceConfig.UMask = "0002";

      system.stateVersion = "25.11";
    };
  };

  # The apps behind nginx at <app>.internal.storage-station.burned.host, one wildcard certificate from Let's Encrypt
  # through Cloudflare's DNS (the name resolves to br0's address on the home network only)
  age.secrets.cloudflare-dns-token.rekeyFile = ./secrets/cloudflare-dns-token.age;
  security.acme = {
    acceptTerms = true;
    defaults.email = "artur.luppov@icloud.com";
    certs."internal.storage-station.burned.host" = {
      domain = "*.internal.storage-station.burned.host";
      dnsProvider = "cloudflare";
      environmentFile = config.age.secrets.cloudflare-dns-token.path;
      group = "nginx";
    };
  };
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    # The names are longer than the default bucket holds
    serverNamesHashBucketSize = 128;
    virtualHosts = {
      "glance.internal.storage-station.burned.host" = {
        forceSSL = true;
        useACMEHost = "internal.storage-station.burned.host";
        locations."/".proxyPass = "http://127.0.0.1:8080";
      };
      "plex.internal.storage-station.burned.host" = {
        forceSSL = true;
        useACMEHost = "internal.storage-station.burned.host";
        locations."/" = {
          proxyPass = "http://127.0.0.1:32400";
          proxyWebsockets = true;
        };
      };
      "radarr.internal.storage-station.burned.host" = {
        forceSSL = true;
        useACMEHost = "internal.storage-station.burned.host";
        locations."/".proxyPass = "http://127.0.0.1:7878";
      };
      "sonarr.internal.storage-station.burned.host" = {
        forceSSL = true;
        useACMEHost = "internal.storage-station.burned.host";
        locations."/".proxyPass = "http://127.0.0.1:8989";
      };
      "prowlarr.internal.storage-station.burned.host" = {
        forceSSL = true;
        useACMEHost = "internal.storage-station.burned.host";
        locations."/".proxyPass = "http://127.0.0.1:9696";
      };
      "qbittorrent.internal.storage-station.burned.host" = {
        forceSSL = true;
        useACMEHost = "internal.storage-station.burned.host";
        locations."/".proxyPass = "http://10.233.1.2:8080";
      };
    };
  };
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  # The clusters reach the iSCSI target on VLAN 33 only
  networking.firewall.interfaces.br33.allowedTCPPorts = [3260];

  # The edge cluster's server k8s-node-x86-64-1, as a NixOS container on VLAN 33 built from its own configuration
  # (path, in flake.nix). k3s runs containers itself: all capabilities and devices, keyring and BPF system calls,
  # /dev/kmsg. Its root is a dataset of its own.
  fileSystems."/var/lib/nixos-containers/edge-server" = {
    device = "tank/edge-server";
    fsType = "zfs";
    options = ["nofail"];
  };
  containers.edge-server = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br33";
    additionalCapabilities = ["all"];
    allowedDevices = [
      {
        node = "char-*";
        modifier = "rwm";
      }
      {
        node = "block-*";
        modifier = "rwm";
      }
    ];
    bindMounts."/dev/kmsg" = {
      hostPath = "/dev/kmsg";
      isReadOnly = false;
    };
    extraFlags = [
      "--system-call-filter=@keyring"
      "--system-call-filter=bpf"
      "--property=MemoryMax=8G"
      "--property=CPUQuota=400%"
    ];
  };
  systemd.services."container@edge-server" = {
    unitConfig.RequiresMountsFor = ["/var/lib/nixos-containers/edge-server"];
    # The container's own shutdown waits up to 90 s for k3s's container shims, which k3s leaves running on stop. Killed
    # at the same 90 s, nspawn would leave its mounts and network link behind and the next start would fail.
    serviceConfig.TimeoutStopSec = "3min";
  };
  # kubelet sets these on start and fails if it can't; they're host-wide, and /proc/sys is read-only in the container
  boot.kernel.sysctl = {
    "vm.overcommit_memory" = 1;
    "kernel.panic" = 10;
    "kernel.panic_on_oops" = 1;
  };
  # k3s in the container relies on these being loaded on the host
  boot.kernelModules = [
    "overlay"
    "br_netfilter"
    "vxlan"
    "nf_tables"
    "nft_compat"
  ];

  services.prometheus.exporters = {
    node = {
      enable = true;
      listenAddress = "127.0.0.1";
    };
    smartctl = {
      enable = true;
      listenAddress = "127.0.0.1";
    };
  };

  services.victoriametrics = {
    enable = true;
    listenAddress = "127.0.0.1:8428";
    retentionPeriod = "90d";
    prometheusConfig.scrape_configs = [
      {
        job_name = "node";
        static_configs = [{targets = ["127.0.0.1:9100"];}];
      }
      {
        job_name = "smartctl";
        static_configs = [{targets = ["127.0.0.1:9633"];}];
      }
    ];
  };

  services.glance = {
    enable = true;
    settings = {
      server = {
        host = "127.0.0.1";
        port = 8080;
      };
      pages = [
        {
          name = "storage-station";
          columns = [
            {
              size = "small";
              widgets = [
                {
                  type = "server-stats";
                  servers = [
                    {
                      type = "local";
                      name = "storage-station";
                    }
                  ];
                }
              ];
            }
            {
              size = "full";
              widgets = [
                {
                  type = "custom-api";
                  title = "ZFS pools";
                  cache = "1m";
                  url = "http://127.0.0.1:8428/api/v1/query";
                  parameters.query = "node_zfs_zpool_state == 1";
                  template = ''
                    <ul class="list list-gap-10">
                    {{ range .JSON.Array "data.result" }}
                      <li>{{ .String "metric.zpool" }}: <span class="{{ if eq (.String "metric.state") "online" }}color-positive{{ else }}color-negative{{ end }}">{{ .String "metric.state" }}</span></li>
                    {{ end }}
                    </ul>
                  '';
                }
                {
                  type = "custom-api";
                  title = "SMART";
                  cache = "5m";
                  url = "http://127.0.0.1:8428/api/v1/query";
                  parameters.query = "smartctl_device_smart_status";
                  template = ''
                    <ul class="list list-gap-10">
                    {{ range .JSON.Array "data.result" }}
                      <li>{{ .String "metric.device" }}: <span class="{{ if eq (.String "value.1") "1" }}color-positive">passed{{ else }}color-negative">FAILED{{ end }}</span></li>
                    {{ end }}
                    </ul>
                  '';
                }
                {
                  type = "monitor";
                  title = "Services";
                  cache = "1m";
                  sites = [
                    {
                      title = "Plex";
                      url = "http://127.0.0.1:32400/identity";
                    }
                    {
                      title = "Sonarr";
                      url = "http://127.0.0.1:8989/ping";
                    }
                    {
                      title = "Radarr";
                      url = "http://127.0.0.1:7878/ping";
                    }
                    {
                      title = "Prowlarr";
                      url = "http://127.0.0.1:9696/ping";
                    }
                    {
                      title = "qBittorrent";
                      url = "http://10.233.1.2:8080/";
                    }
                    {
                      title = "FlareSolverr";
                      url = "http://127.0.0.1:8191/health";
                    }
                  ];
                }
              ];
            }
          ];
        }
      ];
    };
  };
}

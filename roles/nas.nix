{inputs, ...}: {
  flake.nixosModules.nas = {
    config,
    lib,
    pkgs,
    ...
  }: {
    fileSystems = {
      "/home" = {
        device = "tank/home";
        fsType = "zfs";
        options = ["nofail"];
      };
      "/srv/media" = {
        device = "dozer/media";
        fsType = "zfs";
        options = ["nofail"];
      };
      "/srv/3d-models" = {
        device = "dozer/data/3d-models";
        fsType = "zfs";
        options = ["nofail"];
      };
      "/srv/time-machine" = {
        device = "dozer/backups/time-machine";
        fsType = "zfs";
        options = ["nofail"];
      };
      "/srv/vm-archive" = {
        device = "dozer/backups/vm-archive";
        fsType = "zfs";
        options = ["nofail"];
      };
    };

    services.zfs.autoScrub.enable = true;
    services.smartd = {
      enable = true;
      defaults.autodetected = "-a -o on -s (S/../.././02|L/../15/./04)";
    };
    services.sanoid = {
      enable = true;
      templates = {
        production = {
          hourly = 24;
          daily = 14;
          monthly = 3;
        };
        media = {
          hourly = 0;
          daily = 7;
          monthly = 0;
        };
      };
      datasets = {
        "tank/kubernetes" = {
          useTemplate = ["production"];
          recursive = true;
        };
        "tank/kubernetes-edge" = {
          useTemplate = ["production"];
          recursive = true;
        };
        "tank/home" = {
          useTemplate = ["production"];
          recursive = true;
        };
        "tank/apps" = {
          useTemplate = ["production"];
          recursive = true;
        };
        "dozer/data" = {
          useTemplate = ["production"];
          recursive = true;
        };
        "dozer/backups" = {
          useTemplate = ["production"];
          recursive = true;
        };
        "dozer/media" = {
          useTemplate = ["media"];
          recursive = true;
        };
      };
    };

    environment.persistence."/persist".directories = [
      "/var/lib/samba"
      "/var/lib/target"
    ];

    users.users.apps = {
      uid = 568;
      group = "apps";
      isSystemUser = true;
    };
    users.groups = {
      designers.gid = 1002;
      apps.gid = 568;
    };

    services.samba = {
      enable = true;
      openFirewall = true;
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
          "map to guest" = "Bad User";
        };
        "3d-models" = {
          "path" = "/srv/3d-models";
          "read only" = "no";
          "valid users" = "@designers";
          "force group" = "designers";
          "create mask" = "0770";
          "directory mask" = "0770";
        };
        "media" = {
          "path" = "/srv/media/media";
          "read only" = "yes";
          "guest ok" = "yes";
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
      interface = "br0";
    };

    services.k3s.images = [
      (pkgs.dockerTools.buildLayeredImage {
        name = "browser";
        tag = "nix";
        contents = [
          pkgs.dockerTools.fakeNss
          pkgs.cacert
          pkgs.cage
          pkgs.chromium
          pkgs.wayvnc
          pkgs.novnc
          pkgs.python3Packages.websockify
          pkgs.socat
        ];
        config.Env = [
          "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          "FONTCONFIG_FILE=${pkgs.makeFontsConf {
            fontDirectories = [
              pkgs.dejavu_fonts
              pkgs.noto-fonts
              pkgs.noto-fonts-color-emoji
            ];
          }}"
        ];
      })
    ];
    users.users.lintel = {
      uid = 569;
      group = "lintel";
      isSystemUser = true;
    };
    users.groups.lintel.gid = 569;

    # Lintel (edge/media) snapshots its dataset before every writing command, through /dev/zfs as uid 569
    systemd.services.lintel-zfs-delegation = {
      description = "Delegate the 3D models' dataset to the lintel user";
      after = ["zfs-import.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${config.boot.zfs.package}/bin/zfs allow -u lintel snapshot,destroy,mount dozer/data/3d-models";
      };
    };

    # The shares' and the media's datasets are nofail mounts (flake.nix); without them the services would write to
    # the empty directories on the tmpfs root
    systemd.services.samba-smbd.unitConfig.RequiresMountsFor = [
      "/srv/3d-models"
      "/srv/media"
      "/srv/time-machine"
    ];

    networking.firewall.allowedUDPPorts = [
      1900
      5353
      32410
      32412
      32413
      32414
    ];

    networking.firewall.interfaces.cni0.allowedTCPPorts = [
      7878
      8989
      9696
      8191
      32400
    ];
    networking.firewall.allowedTCPPorts = [
      32400
      3005
      8324
      32469
    ];

    networking.firewall.interfaces.br33.allowedTCPPorts = [3260];
  };
}

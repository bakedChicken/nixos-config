{
  flake.nixosModules.storage-station-hardware = {config, ...}: {
    boot.kernelParams = [
      "console=tty0"
      "console=ttyS0,115200"
      # The stacks of tasks blocked for 20s, in both boot stages: tank's SSDs stall for longer, and the
      # KernelBug alert reads these reports
      "sysctl.kernel.hung_task_timeout_secs=20"
    ];
    boot.initrd.availableKernelModules = [
      "ahci"
      "xhci_pci"
      "usb_storage"
      "uas"
      "sd_mod"
      "igc"
      "atlantic"
    ];

    boot.initrd.network.enable = true;
    boot.initrd.network.ssh = {
      enable = true;
      port = 2222;
      hostKeys = ["/persist/etc/ssh/ssh_host_ed25519_initrd_key"];
      authorizedKeys = config.users.users.artur.openssh.authorizedKeys.keys;
    };
    boot.initrd.systemd.network.networks."10-enp5s0" = {
      matchConfig.Name = "enp5s0";
      networkConfig.DHCP = "yes";
    };
    # enp5s0 becomes a bridge port in the system; its initrd address must not stay on it
    boot.initrd.network.flushBeforeStage2 = true;

    boot.loader.systemd-boot.bootCounting = {
      enable = true;
      tries = 2;
    };
    systemd.services.boot-health = {
      description = "Network and SSH are up, so this generation is good";
      before = ["boot-complete.target"];
      requiredBy = ["boot-complete.target"];
      wants = [
        "network-online.target"
        "sshd.service"
      ];
      after = [
        "network-online.target"
        "sshd.service"
      ];
      unitConfig.FailureAction = "reboot";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${config.systemd.package}/bin/systemctl is-active --quiet sshd.service network-online.target";
      };
    };

    hardware.enableRedistributableFirmware = true;
    hardware.cpu.amd.updateMicrocode = true;
    boot.kernelModules = ["sp5100_tco"];

    fileSystems = {
      "/nix" = {
        device = "tank/system/nix";
        fsType = "zfs";
      };
      "/persist" = {
        device = "tank/system/persist";
        fsType = "zfs";
      };
    };

    boot.zfs.forceImportRoot = false;
    boot.zfs.extraPools = ["dozer"];
    networking.hostId = "7bbabf8f";

    services.avahi.settings.server.allow-interfaces = [
      "br0"
      "br33"
    ];
    systemd.network = {
      netdevs = {
        "10-br0".netdevConfig = {
          Kind = "bridge";
          Name = "br0";
        };
        "10-br33".netdevConfig = {
          Kind = "bridge";
          Name = "br33";
        };
        "10-vlan33" = {
          netdevConfig = {
            Kind = "vlan";
            Name = "vlan33";
          };
          vlanConfig.Id = 33;
        };
      };
      networks = {
        "10-enp5s0" = {
          matchConfig.Name = "enp5s0";
          networkConfig = {
            Bridge = "br0";
            VLAN = ["vlan33"];
          };
        };
        "10-br33-ports" = {
          matchConfig.Name = "vlan33 enp6s0 enp7s0";
          networkConfig.Bridge = "br33";
          linkConfig.RequiredForOnline = "no";
        };
        "20-br0" = {
          matchConfig.Name = "br0";
          networkConfig = {
            DHCP = "yes";
            IPv6AcceptRA = true;
          };
          dhcpV4Config.ClientIdentifier = "mac";
        };
        "20-br33" = {
          matchConfig.Name = "br33";
          networkConfig = {
            DHCP = "yes";
            IPv6AcceptRA = true;
          };
          dhcpV4Config = {
            ClientIdentifier = "mac";
            UseGateway = false;
            IPv6OnlyMode = true;
          };
          ipv6AcceptRAConfig.UseGateway = false;
          routingPolicyRules = [
            {
              To = config.kubernetes.cluster.clusterCidr;
              Table = "main";
              Priority = 99;
            }
            {
              From = "fd71:895d:e328:33::/64";
              Table = 33;
              Priority = 100;
            }
          ];
          routes = [
            {
              Destination = "fd71:895d:e328:33::/64";
              Table = 33;
            }
            {
              Gateway = "_ipv6ra";
              Table = 33;
            }
          ];
          linkConfig.RequiredForOnline = "no";
        };
      };
    };
  };
}

{
  flake.nixosModules.storage-station-hardware = {
    boot.kernelParams = [
      "console=tty0"
      "console=ttyS0,115200"
    ];
    boot.initrd.availableKernelModules = [
      "ahci"
      "xhci_pci"
      "usb_storage"
      "uas"
      "sd_mod"
    ];
    hardware.enableRedistributableFirmware = true;
    hardware.cpu.amd.updateMicrocode = true;
    boot.kernelModules = ["sp5100_tco"];
    systemd.settings.Manager = {
      RuntimeWatchdogSec = "30s";
      RebootWatchdogSec = "10min";
    };

    boot.loader.systemd-boot.extraEntries."systemrescue.conf" = ''
      title SystemRescue 13.02
      linux /sysresccd/boot/x86_64/vmlinuz
      initrd /sysresccd/boot/x86_64/sysresccd.img
      options archisobasedir=sysresccd archisolabel=RESCUE1302
    '';

    fileSystems = {
      "/boot" = {
        device = "/dev/disk/by-id/usb-_USB_DISK_MODULE_19001154C7B52558-0:0-part1";
        fsType = "vfat";
        options = ["umask=0077"];
      };
      "/nix" = {
        device = "tank/system/nix";
        fsType = "zfs";
        neededForBoot = true;
      };
      "/persist" = {
        device = "tank/system/persist";
        fsType = "zfs";
      };
    };

    boot.supportedFilesystems.zfs = true;
    boot.zfs.forceImportRoot = false;
    boot.zfs.extraPools = ["dozer"];
    networking.hostId = "7bbabf8f";

    networking.networkmanager.settings.main.no-auto-default = "*";
    services.avahi.allowInterfaces = [
      "br0"
      "br33"
    ];
    networking.networkmanager.ensureProfiles.profiles = {
      br0 = {
        connection = {
          id = "br0";
          type = "bridge";
          interface-name = "br0";
        };
        bridge.stp = false;
        ipv4.method = "auto";
        ipv6.method = "auto";
      };
      br0-enp5s0 = {
        connection = {
          id = "br0-enp5s0";
          type = "ethernet";
          interface-name = "enp5s0";
          controller = "br0";
          port-type = "bridge";
        };
      };
      br33 = {
        connection = {
          id = "br33";
          type = "bridge";
          interface-name = "br33";
        };
        bridge.stp = false;
        ipv4 = {
          method = "auto";
          never-default = true;
        };
        ipv6 = {
          method = "auto";
          never-default = true;
        };
      };
      br33-vlan33 = {
        connection = {
          id = "br33-vlan33";
          type = "vlan";
          interface-name = "vlan33";
          controller = "br33";
          port-type = "bridge";
        };
        vlan = {
          parent = "enp5s0";
          id = 33;
        };
      };
      br33-enp6s0 = {
        connection = {
          id = "br33-enp6s0";
          type = "ethernet";
          interface-name = "enp6s0";
          controller = "br33";
          port-type = "bridge";
        };
      };
      br33-enp7s0 = {
        connection = {
          id = "br33-enp7s0";
          type = "ethernet";
          interface-name = "enp7s0";
          controller = "br33";
          port-type = "bridge";
        };
      };
    };
  };
}

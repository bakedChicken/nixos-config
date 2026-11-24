let
  esp = {
    start = "1M";
    type = "EF00";
    content = {
      type = "filesystem";
      format = "vfat";
      mountpoint = "/boot";
      mountOptions = ["umask=0077"];
    };
  };
in
{
  flake.diskoConfigurations.vm = {
    disko.devices.disk.main = {
      device = "/dev/sda";
      content = {
        type = "gpt";
        partitions = {
          ESP = esp // {
            end = "512M";
          };
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = ["-f"];
              subvolumes = {
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "/persist" = {
                  mountpoint = "/persist";
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
  };

  flake.diskoConfigurations.storage-station = {
    disko.devices.disk.main = {
      device = "/dev/disk/by-id/usb-_USB_DISK_MODULE_19001154C7B52558-0:0";
      content = {
        type = "gpt";
        partitions = {
          ESP = esp // {
            size = "100%";
          };
        };
      };
    };
  };
}

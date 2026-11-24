{inputs, ...}: {
  flake.nixosModules.raspberry-pi-3 = {modulesPath, ...}: {
    imports = [
      "${modulesPath}/profiles/minimal.nix"
      inputs.nixos-raspberry-pi-uefi.nixosModules.default
    ];

    hardware.pi3.uefi.enable = true;
    boot.loader.systemd-boot.enable = true;
    fileSystems."/".fsType = "btrfs";

    services.journald.settings.Journal = {
      Storage = "volatile";
      RuntimeMaxUse = "16M";
    };
  };
}

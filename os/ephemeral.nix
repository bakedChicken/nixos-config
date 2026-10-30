{
  flake.nixosModules.ephemeral = {
    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=25%"
        "mode=755"
      ];
    };
    fileSystems."/persist".neededForBoot = true;

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    system.etc.overlay.enable = true;
    system.etc.overlay.mutable = false;
    services.userborn.enable = true;
    users.mutableUsers = false;

    environment.persistence."/persist" = {
      hideMounts = true;
      directories = [
        "/var/lib/nixos"
        "/var/lib/systemd"
        "/var/lib/NetworkManager"
        "/var/log"
      ];
    };

    services.openssh.hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
    age.identityPaths = ["/persist/etc/ssh/ssh_host_ed25519_key"];
    environment.etc."machine-id".source = "/persist/etc/machine-id";
    systemd.tmpfiles.rules = [
      "d /persist 0755 root root - -"
      "d /persist/etc 0755 root root - -"
    ];
  };
}

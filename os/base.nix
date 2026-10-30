{
  self,
  inputs,
  ...
}: {
  flake.nixosModules.base = {
    lib,
    pkgs,
    ...
  }: {
    imports = [
      self.nixosModules.common
      inputs.agenix.nixosModules.default
      inputs.agenix-rekey.nixosModules.default
      inputs.impermanence.nixosModules.impermanence
      inputs.disko.nixosModules.disko
    ];

    boot.loader.systemd-boot.configurationLimit = 10;

    boot.kernelPackages = pkgs.linuxPackages_latest;

    zramSwap.enable = true;

    networking.useDHCP = false;
    networking.networkmanager = {
      enable = true;
      settings.connection = {
        "ipv4.dhcp-client-id" = "mac";
        "ipv4.dhcp-ipv6-only-preferred" = 2;
        "ipv4.clat" = 1;
        "ipv6.addr-gen-mode" = 0;
        "ipv6.ip6-privacy" = 0;
        "ipv6.dhcp-duid" = "ll";
      };
    };

    networking.usePredictableInterfaceNames = false;
    networking.wireless.enable = lib.mkForce false;

    services.avahi = {
      enable = true;
      nssmdns4 = true;
      nssmdns6 = true;
      publish = {
        enable = true;
        userServices = true;
        domain = true;
      };
    };
    services.avahi.allowInterfaces = ["eth0"];
    # systemd would create /etc/avahi/services for the daemon, which fails on a read-only /etc
    systemd.services.avahi-daemon.serviceConfig.ConfigurationDirectory = lib.mkForce "";
    # resolved owns resolv.conf (/etc is read-only on most machines); avahi alone answers mDNS: resolved
    # takes its own name repeated back by the router for a conflict and renames itself endlessly
    services.resolved = {
      enable = true;
      settings.Resolve = {
        MulticastDNS = false;
        LLMNR = false;
      };
    };

    services.openssh = {
      enable = true;
      authorizedKeysInHomedir = false;
      hostKeys = lib.mkDefault [
        {
          path = "/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];
    };
    security.sudo.wheelNeedsPassword = false;

    systemd.enableEmergencyMode = false;

    documentation.enable = false;
    documentation.nixos.enable = false;
    system.stateVersion = "25.11";
  };
}

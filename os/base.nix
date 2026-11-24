{
  self,
  inputs,
  ...
}: {
  flake.nixosModules.base = {lib, ...}: {
    imports = [
      self.nixosModules.common
      inputs.agenix.nixosModules.default
      inputs.agenix-rekey.nixosModules.default
      inputs.impermanence.nixosModules.impermanence
      inputs.disko.nixosModules.disko
    ];

    boot.loader.systemd-boot.configurationLimit = 10;

    zramSwap.enable = true;

    networking.useDHCP = false;
    networking.useNetworkd = true;
    systemd.network = {
      wait-online.anyInterface = true;
      networks."90-ethernet" = {
        matchConfig = {
          Type = "ether";
          Kind = "!*";
        };
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        dhcpV4Config = {
          ClientIdentifier = "mac";
          IPv6OnlyMode = true;
        };
      };
    };
    services.clatd.enable = true;
    systemd.services.clatd.serviceConfig = {
      Restart = "on-failure";
      RestartSec = "10s";
    };

    networking.domain = "internal.burned.host";
    services.resolved = {
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

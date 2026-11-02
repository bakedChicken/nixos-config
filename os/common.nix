let
  common = {config, ...}: {
    nix = {
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        trusted-users = [
          "root"
          "@wheel"
          "@admin"
        ];
        min-free = 20 * 1024 * 1024 * 1024;
        max-free = 60 * 1024 * 1024 * 1024;
        extra-substituters = ["http://172.16.33.53:5000?priority=30"];
        extra-trusted-public-keys = ["storage-station.local-1:fIEPn2Z8C/0WGt23IqPnpTfwLSq62ebE6Df3mRMjQs0="];
        connect-timeout = 3;
        fallback = true;
      };
      channel.enable = false;
      optimise.automatic = true;
      gc = {
        automatic = true;
        options = "--delete-older-than 7d";
      };
    };
    time.timeZone = "Europe/Vienna";

    age.rekey = {
      storageMode = "local";
      localStorageDir = ./.. + "/rekeyed/${config.networking.hostName}";
      masterIdentities = ["/Users/yoba/.ssh/id_ed25519"];
    };
  };
in {
  flake.nixosModules.common = common;
  flake.darwinModules.common = common;
}

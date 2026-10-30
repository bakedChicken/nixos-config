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
      };
      channel.enable = false;
      optimise.automatic = true;
      gc = {
        automatic = true;
        options = "--delete-older-than 30d";
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

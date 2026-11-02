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
        # Collect garbage while building once free space drops below 20 GiB, until 60 GiB are free,
        # instead of waiting for the weekly run
        min-free = 21474836480;
        max-free = 64424509440;
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

{self, ...}: {
  flake.darwinModules.yoba = {pkgs, ...}: {
    system.primaryUser = "yoba";
    users.knownUsers = ["yoba"];
    users.users.yoba = {
      uid = 501;
      home = "/Users/yoba";
      shell = pkgs.bashInteractive;
    };
    environment.shells = [pkgs.bashInteractive];

    # The LG UltraGear's inputs over DDC (LG's addressing): DisplayPort 2, HDMI 1
    services.skhd = {
      enable = true;
      skhdConfig = ''
        f13 : ${pkgs.m1ddc}/bin/m1ddc display 1D616FC7-1B39-4269-8535-59EAA0EF7D2D set input-alt 209
        f14 : ${pkgs.m1ddc}/bin/m1ddc display 1D616FC7-1B39-4269-8535-59EAA0EF7D2D set input-alt 144
      '';
    };

    age.secrets.ghcr-token = {
      rekeyFile = ../kubernetes/secrets/ghcr-token.age;
      owner = "yoba";
      mode = "0400";
    };

    home-manager.users.yoba = {
      imports = [self.homeModules.artur];

      home.packages = with pkgs; [
        btop
        m1ddc
        picocom
        rectangle
      ];
    };
  };
}

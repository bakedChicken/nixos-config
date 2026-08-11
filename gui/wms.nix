{ self, ... }:
{
  flake = {
    homeModules.wm = { pkgs, ... }: {
      home.pointerCursor = {
        enable = true;
        package = pkgs.kdePackages.breeze;
        name = "breeze_cursors";
        size = 16;
      };
    };

    nixosModules.wm = { pkgs, ... }: {
      services.getty = {
        autologinUser = "artur";
      };
      services.greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd sway";
            user = "artur";
          };
        };
      };
      home-manager.users.artur.imports = [
        self.homeModules.wm
      ];
    };
  };
}

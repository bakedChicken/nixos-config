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
      services.displayManager = {
        enable = true;
        sddm = {
          enable = true;
          wayland.enable = true;
        };
        autoLogin = {
          enable = true;
          user = "artur";
        };
      };

      services.pipewire = {
        enable = true;
        alsa.enable = true;
        pulse.enable = true;
      };

      environment.systemPackages = with pkgs; [
        htop
        wlr-randr
      ];

      home-manager.users.artur.imports = [
        self.homeModules.wm
      ];
    };
  };
}

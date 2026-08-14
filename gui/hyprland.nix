{ self, ... }:
{
  flake = {
    homeModules = {
      hyprland-home = {
        wayland.windowManager.hyprland = {
          enable = true;
          configType = "lua";
          package = null;
          portalPackage = null;
          settings = {
            mod = {
              _var = "SUPER";
            };

            monitor = {
              output = "Virtual-1";
              mode = "1920x1080@60";
              position = "0x0";
              scale = 1;
            };
          };
        };
      };
    };

    nixosModules = {
      hyprland = {
        programs.hyprland = {
          enable = true;
          xwayland.enable = true;
        };
        home-manager.users.artur.imports = [
          self.homeModules.hyprland-home
        ];
      };
    };
  };
}

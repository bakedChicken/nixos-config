{ self, ... }:
{
  flake = {
    homeModules = {
      hyprland-home = { pkgs, ... }: {
        programs.kitty.enable = true; # required for the default Hyprland config
        wayland.windowManager.hyprland = {
          enable = true;
          configType = "lua";
          package = null;
          portalPackage = null;
          settings = {
            "$mod" = "Super";
          };
        };
        home.sessionVariables.NIXOS_OZONE_WL = "1";
        home.pointerCursor = {
          package = pkgs.kdePackages.breeze;
          name = "breeze_cursors";
          size = 16;
        };
        programs.bash.profileExtra = ''
          if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
            exec uwsm start -S hyprland-uwsm.desktop
          fi
        '';
      };
    };

    nixosModules = {
      hyprland =
        { pkgs, ... }:
        {
          services.getty.autologinUser = "artur";
          home-manager.users.artur.imports = [
            self.homeModules.hyprland-home
          ];
        };
    };
  };
}

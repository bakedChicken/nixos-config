{ self, ... }:
{
  flake = {
    homeModules = {
      hyprland-home = { pkgs, ... }: {
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
          programs.hyprland = {
            enable = true;
            withUWSM = true;
            xwayland.enable = true;
          };
          environment.systemPackages = with pkgs; [
            #wayland-utils
            #wl-clipboard
            kitty
          ];
          home-manager.users.artur.imports = [
            self.homeModules.hyprland-home
          ];
        };
    };
  };
}

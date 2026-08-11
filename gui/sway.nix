{ self, ... }:
{
  flake.homeModules.sway = { pkgs, ... }: {
    wayland.windowManager.sway = {
      enable = true;
      systemd.enable = true;
      systemd.variables = [ "--all" ];
      wrapperFeatures.gtk = true;
      config = {
        modifier = "Mod1";
        terminal = "alacritty";
        output = {
          Virtual-1 = {
            mode = "--custom 3024x1890@60Hz";
            scale = "2";
          };
        };
      };
    };
  };

  flake.nixosModules.sway = { pkgs, ... }: {
    security.polkit.enable = true;
    environment.loginShellInit = ''
      [[ "$(tty)" == /dev/tty1 ]] && sway
    '';
    home-manager.users.artur.imports = [
      self.homeModules.sway
    ];
  };
}

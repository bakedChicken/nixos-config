{ self, ... }:
{
  flake.homeModules.sway = {
    wayland.windowManager.sway = {
      enable = true;
      systemd.enable = true;
      systemd.variables = [ "--all" ];
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

    xdg.portal = {
      enable = true;
      wlr.enable = true;
    };

    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
    };
    environment.systemPackages = with pkgs; [
      mako
    ];
    home-manager.users.artur.imports = [
      self.homeModules.sway
    ];
  };
}

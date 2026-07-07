{ self, ... }:
{
  flake.homeModules.sway = { pkgs, ... }: {
    home.pointerCursor = {
      package = pkgs.kdePackages.breeze;
      name = "breeze_cursors";
      size = 16;
    };
    wayland.windowManager.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
      config = {
        modifier = "Mod1";
        terminal = "alacritty";
      };
    };
  };

  flake.nixosModules.sway = {
    security.polkit.enable = true;
    services.getty = {
      autologinUser = "artur";
      autologinOnce = true;
    };
    environment.loginShellInit = ''
      [[ "$(tty)" == /dev/tty1 ]] && sway
    '';
    home-manager.users.artur.imports = [
      self.homeModules.sway
    ];
  };
}

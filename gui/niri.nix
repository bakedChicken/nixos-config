{ inputs, ... }:
{
  imports = [
    inputs.home-manager.flakeModules.home-manager
  ];

  flake = {
    homeModules.niri-wm =
      { pkgs, ... }:
      {
        programs.niri = {
          enable = true;
          package = pkgs.niri;
        };
        programs.noctalia-shell.enable = true;
        programs.fuzzel.enable = true;
      };

    nixosModules.niri-wm = {
      environment.pathsToLink = [
        "/share/applications"
        "/share/xdg-desktop-portal"
      ];
      services.displayManager.ly.enable = true;

      home-manager.users.artur.imports = [
        inputs.niri-flake.homeModules.niri
        inputs.noctalia-flake.homeModules.default
        inputs.self.homeModules.niri-wm
      ];
    };
  };
}

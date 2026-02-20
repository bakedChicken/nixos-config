{ inputs, ... }:
{
  imports = [
    inputs.home-manager.flakeModules.home-manager
  ];

  flake = {
    homeModules.niri-wm = {
      programs.noctalia-shell.enable = true;
      programs.fuzzel.enable = true;
    };

    nixosModules.niri-wm =
      { pkgs, ... }:
      {
        environment.pathsToLink = [
          "/share/applications"
          "/share/xdg-desktop-portal"
        ];
        services.displayManager.defaultSession = "niri";
        programs.niri.enable = true;

        home-manager.users.artur.imports = [
          inputs.noctalia-flake.homeModules.default
          inputs.self.homeModules.niri-wm
        ];
      };
  };
}

{ inputs, ... }:
{
  flake = {
    homeModules.niri-wm = {
      programs.noctalia-shell.enable = true;
      programs.fuzzel.enable = true;
      programs.swaylock.enable = true;
    };

    nixosModules.niri-wm =
      { pkgs, ... }:
      {
        environment.pathsToLink = [
          "/share/applications"
          "/share/xdg-desktop-portal"
        ];

        programs.niri.enable = true;

        environment.systemPackages = with pkgs; [
          xwayland-satellite
        ];

        home-manager.users.artur.imports = [
          inputs.noctalia-flake.homeModules.default
          inputs.self.homeModules.niri-wm
        ];
      };
  };
}

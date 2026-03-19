{ inputs, ... }:
{
  imports = [
    inputs.home-manager.flakeModules.home-manager
  ];

  flake = {
    homeModules.niri-wm =
      { pkgs, ... }:
      {
        programs.noctalia-shell.enable = true;
        programs.fuzzel.enable = true;
        programs.alacritty.enable = true;
        programs.swaylock.enable = true;

        home.pointerCursor = {
          package = pkgs.kdePackages.breeze;
          name = "breeze_cursors";
          size = 16;
        };
      };

    nixosModules.niri-wm =
      { pkgs, ... }:
      {
        environment.pathsToLink = [
          "/share/applications"
          "/share/xdg-desktop-portal"
        ];

        services.displayManager.ly.enable = true;
        services.displayManager.defaultSession = "niri";
        programs.niri.enable = true;

	environment.systemPackages = with pkgs; [
	  xwayland-satellite
	];

        home-manager.users.nobile.imports = [
          inputs.noctalia-flake.homeModules.default
          inputs.self.homeModules.niri-wm
        ];
      };
  };
}

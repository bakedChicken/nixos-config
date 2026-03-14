{ inputs, ... }:
{
  imports = [
    inputs.home-manager.flakeModules.home-manager
  ];

  flake = {
    homeModules.nobile =
      { pkgs, ... }:
      {
        home = {
          username = "nobile";
          homeDirectory = "/home/nobile";
          stateVersion = "25.11";
          preferXdgDirectories = true;
          packages = with pkgs; [
            jetbrains.rider
            remmina
            slack
            firefox-devedition
          ];
        };

        xdg.enable = true;
        systemd.user.startServices = "sd-switch";

        programs.git = {
          enable = true;
          settings.user = {
            name = "Artur Luppov";
            email = "artur.luppov@icloud.com";
          };
        };

        programs.kitty.enable = true;
        programs.zed-editor.enable = true;
        programs.zed-editor.extensions = [
          "nix"
          "go"
          "csharp"
        ];
        programs.direnv.enable = true;
        programs.starship.enable = true;
      };

    nixosModules.nobile =
      { pkgs, ... }:
      {
        users.users.nobile = {
          description = "Artur Luppov";
          isNormalUser = true;
          extraGroups = [
            "wheel"
            "video"
            "audio"
          ];
          hashedPassword = "$6$Uk57TgLuIsocbW6m$Y1Ljj7fP4/m5dMQkMFa2Nrs0hUDcF.62qONruluGtIDS8LtLog7SAuYU7dbOMexLyJX0z7YohILhCToUt8hHa0";
          shell = pkgs.powershell;
        };

        environment.variables = {
          ZED_ALLOW_EMULATED_GPU = 1;
        };

        home-manager.users.nobile.imports = [
          inputs.self.homeModules.nobile
        ];
      };
  };
}

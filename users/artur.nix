{ inputs, ... }:
{
  imports = [
    inputs.home-manager.flakeModules.home-manager
  ];

  flake = {
    homeModules.artur =
      { pkgs, ... }:
      {
        home = {
          username = "artur";
          homeDirectory = "/home/artur";
          stateVersion = "25.11";
          preferXdgDirectories = true;
          packages = with pkgs; [
            kubectl
            k9s
            jetbrains-toolbox
          ];
        };

        xdg.enable = true;
        systemd.user.startServices = "sd-switch";

        programs.bash = {
          enable = true;
          historyControl = [ "ignoredups" ];
        };

        programs.git = {
          enable = true;
          settings.user = {
            name = "Artur Luppov";
            email = "artur.luppov@icloud.com";
          };
        };

        programs.firefox.enable = true;
        programs.direnv.enable = true;
        programs.starship.enable = true;
      };

    nixosModules.artur =
      { pkgs, ... }:
      {
        users.users.artur = {
          description = "Artur Luppov";
          isNormalUser = true;
          extraGroups = [
            "wheel"
            "video"
            "audio"
            "networkmanager"
          ];
          hashedPassword = "$6$Uk57TgLuIsocbW6m$Y1Ljj7fP4/m5dMQkMFa2Nrs0hUDcF.62qONruluGtIDS8LtLog7SAuYU7dbOMexLyJX0z7YohILhCToUt8hHa0";
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHDUMJQzDn3WbH69QhZVvej8JpCn6b6jUi4ZpHU952sG artur"
          ];
          shell = pkgs.bash;
        };

        home-manager.users.artur.imports = [
          inputs.self.homeModules.artur
        ];
      };
  };
}

{ inputs, ... }:
{
  flake = {
    homeModules.artur =
      { ... }:
      {
        home = {
          username = "artur";
          homeDirectory = "/home/artur";
          stateVersion = "25.11";
          preferXdgDirectories = true;
        };

        programs.kitty.enable = true;
        programs.firefox.enable = true;
        programs.zed-editor.enable = true;
        programs.zed-editor.extensions = [ "nix" ];

        programs.git = {
          enable = true;
          settings.user = {
            name = "Artur Luppov";
            email = "artur.luppov@icloud.com";
          };
        };

        xdg.enable = true;
        systemd.user.startServices = "sd-switch";
      };

    nixosModules.artur =
      { pkgs, ... }:
      {
        imports = [ inputs.home-manager.nixosModules.home-manager ];

        users.users.artur = {
          description = "Artur Luppov";
          isNormalUser = true;
          extraGroups = [ "wheel" ];
          hashedPassword = "$6$Uk57TgLuIsocbW6m$Y1Ljj7fP4/m5dMQkMFa2Nrs0hUDcF.62qONruluGtIDS8LtLog7SAuYU7dbOMexLyJX0z7YohILhCToUt8hHa0";
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHDUMJQzDn3WbH69QhZVvej8JpCn6b6jUi4ZpHU952sG artur"
          ];
          shell = pkgs.bash;
        };

        home-manager.users.artur.imports = [ inputs.self.homeModules.artur ];
      };
  };
}

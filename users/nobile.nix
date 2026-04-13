{ inputs, ... }:
{
  imports = [
    inputs.home-manager.flakeModules.home-manager
  ];

  flake = {
    overlays.rider = (
      final: prev: {
        jetbrains = prev.jetbrains // {
          rider = prev.jetbrains.rider.overrideAttrs rec {
            version = "2026.1.0.1";
            buildNumber = "261.22158.394";

            src = prev.fetchurl {
              url = "https://download-cdn.jetbrains.com/rider/JetBrains.Rider-${version}.tar.gz";
              sha256 = "sha256-moIysTTsq7abpQfNh1Bc5Pk6VQgJIT6erbyHsUXf15Y=";
            };

            autoPatchelfIgnoreMissingDeps = [
              "libcrypt.so.1"
              "libcrypto.so.1.1"
              "libssl.so.1.1"
            ];
          };
        };
      }
    );

    homeModules.nobile =
      { pkgs, ... }:
      {
        home = {
          username = "nobile";
          homeDirectory = "/home/nobile";
          stateVersion = "25.11";
          preferXdgDirectories = true;
          packages = with pkgs; [
            remmina
            slack
            firefox-devedition
            kdePackages.dolphin
            rsync
            jetbrains.rider
          ];

          file.".config/powershell/Microsoft.PowerShell_profile.ps1".text = ''
            Invoke-Expression "$(direnv hook pwsh)"
          '';
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
            "kvm"
            "networkmanager"
          ];
          hashedPassword = "$6$Uk57TgLuIsocbW6m$Y1Ljj7fP4/m5dMQkMFa2Nrs0hUDcF.62qONruluGtIDS8LtLog7SAuYU7dbOMexLyJX0z7YohILhCToUt8hHa0";
          shell = pkgs.powershell;
        };

        networking.wg-quick.interfaces = {
          wg0 = {
            configFile = "/etc/wireguard/wg.conf";
          };
        };

        nixpkgs.overlays = [
          inputs.self.overlays.rider
        ];

        home-manager.users.nobile.imports = [
          inputs.self.homeModules.nobile
        ];
      };
  };
}

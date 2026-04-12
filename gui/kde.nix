{ inputs, ... }:
{
  flake.nixosModules = {
    xrdp = {
      services.xrdp = {
        enable = true;
        openFirewall = true;
        audio.enable = true;
        defaultWindowManager = "startplasma-x11";
      };
    };

    xserver = {
      imports = [
        inputs.self.nixosModules.xrdp
      ];

      services.xserver = {
        enable = true;
        autoRepeatDelay = 200;
        autoRepeatInterval = 35;
      };
    };

    kde-desktop =
      { pkgs, ... }:
      {
        services.desktopManager.plasma6.enable = true;
        services.displayManager.sddm.enable = true;

        environment.plasma6.excludePackages = with pkgs; [
          kdePackages.elisa
          kdePackages.kate
          kdePackages.gwenview
          kdePackages.okular
          kdePackages.kinfocenter
          kdePackages.khelpcenter
          kdePackages.plasma-systemmonitor
          kdePackages.qrca
        ];

        environment.systemPackages = [
          pkgs.kdePackages.kzones
        ];
      };

    wayland =
      { pkgs, ... }:
      {
        services = {
          displayManager.sddm.wayland.enable = true;
        };

        environment.systemPackages = with pkgs; [
          kdePackages.bluedevil
          wayland-utils
          wl-clipboard
        ];
      };
  };
}

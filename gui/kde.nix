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
          kdePackages.elisa # Simple music player aiming to provide a nice experience for its users
          kdePackages.kate
          kdePackages.gwenview
          kdePackages.okular
          kdePackages.kinfocenter
          kdePackages.khelpcenter
          kdePackages.plasma-systemmonitor
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

        networking.firewall.allowedTCPPorts = [ 3389 ];

        environment.systemPackages = with pkgs; [
          kdePackages.krdp
          # KDE
          wayland-utils
          wl-clipboard
        ];
      };
  };
}

{self, ...}: {
  flake.nixosModules = {
    xserver = {
      services.xrdp = {
        enable = true;
        openFirewall = true;
        audio.enable = true;
        defaultWindowManager = "startplasma-x11";
      };

      services.xserver = {
        enable = true;
        autoRepeatDelay = 200;
        autoRepeatInterval = 35;
      };
    };

    wayland = {
      networking.firewall.allowedTCPPorts = [3389];
      services.displayManager.sddm.wayland.enable = true;
    };

    kde-desktop = {pkgs, ...}: {
      imports = [
        self.nixosModules.wayland
      ];

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
        kdePackages.konsole
        kdePackages.ark
        kdePackages.dolphin
        kdePackages.dolphin-plugins
        kdePackages.baloo-widgets
        kdePackages.ffmpegthumbs
        kdePackages.spectacle
        kdePackages.krdp
        kdePackages.discover
        kdePackages.plasma-keyboard
        kdePackages.qtvirtualkeyboard
      ];

      environment.systemPackages = [
        pkgs.kdePackages.kzones
      ];
    };
  };
}

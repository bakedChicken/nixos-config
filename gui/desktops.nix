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

    kde-desktop = {
      imports = [
        inputs.self.nixosModules.xrdp
      ];

      services.xserver = {
        enable = true;
        autoRepeatDelay = 200;
        autoRepeatInterval = 35;
      };

      services.desktopManager.plasma6.enable = true;
      services.displayManager.sddm.enable = true;
    };

    sunshine =
      { pkgs, ... }:
      {
        services.sunshine.enable = true;
        services.sunshine.capSysAdmin = true;
        services.sunshine.openFirewall = true;
        hardware.uinput.enable = true;
      };

    kde-wayland =
      { pkgs, ... }:
      {
        services = {
          desktopManager.plasma6.enable = true;
          displayManager.sddm.enable = true;
          displayManager.sddm.wayland.enable = true;
        };

        environment.plasma6.excludePackages = with pkgs; [
          kdePackages.elisa # Simple music player aiming to provide a nice experience for its users
          kdePackages.kate
          kdePackages.gwenview
          kdePackages.okular
        ];

        environment.systemPackages = with pkgs; [
          kdePackages.krdp
          # KDE
          wayland-utils # Wayland utilities
          wl-clipboard # Command-line copy/paste utilities for Wayland
        ];
      };
  };
}

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
  };
}

{inputs, ...}: let
  shared = {pkgs, ...}: {
    nixpkgs.config.allowUnfree = true;
    fonts.packages = [pkgs.nerd-fonts.fira-code];
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
  };
in {
  flake.nixosModules.workstation = {pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.default
      shared
    ];
    boot.kernelPackages = pkgs.linuxPackages_latest;
  };

  flake.darwinModules.workstation = {
    imports = [
      inputs.home-manager.darwinModules.default
      shared
    ];

    system.defaults.dock = {
      show-recents = false;
    };
  };

  flake.nixosModules.desktop-kde = {pkgs, ...}: {
    services.xserver.enable = true;

    services.desktopManager.plasma6.enable = true;
    services.displayManager.sddm.enable = true;

    environment.etc = {
      "xdg/kcmfonts".text = ''
        [General]
        forceFontDPI=192
      '';
      "xdg/kcminputrc".text = ''
        [Mouse]
        cursorSize=24
      '';
      "xdg/kscreenlockerrc".text = ''
        [Daemon]
        Autolock=false
        LockOnResume=false
      '';
      "xdg/powerdevilrc".text = ''
        [AC][Display]
        DimDisplayWhenIdle=false
        TurnOffDisplayWhenIdle=false

        [AC][SuspendAndShutdown]
        AutoSuspendAction=0
      '';
    };

    programs.kde-pim.enable = false;
    services.orca.enable = false;
    services.xserver.excludePackages = [pkgs.xterm];

    environment.plasma6.excludePackages = with pkgs; [
      kdePackages.elisa
      kdePackages.kate
      kdePackages.gwenview
      kdePackages.okular
      kdePackages.khelpcenter
      kdePackages.konsole
      kdePackages.ark
      kdePackages.baloo-widgets
      kdePackages.krdp
      kdePackages.discover
      kdePackages.plasma-keyboard
      kdePackages.qtvirtualkeyboard
    ];

    environment.systemPackages = [
      pkgs.kdePackages.kzones
    ];
  };
}

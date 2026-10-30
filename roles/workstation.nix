{inputs, ...}: let
  shared = {pkgs, ...}: {
    nixpkgs.config.allowUnfree = true;
    fonts.packages = [pkgs.nerd-fonts.fira-code];
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
  };
in {
  flake.nixosModules.workstation = {
    imports = [
      inputs.home-manager.nixosModules.default
      shared
    ];
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
    services.xrdp = {
      enable = true;
      port = 3390;
      openFirewall = true;
      audio.enable = true;
      defaultWindowManager = "startplasma-x11";
      sslKey = "/var/lib/xrdp/key.pem";
      sslCert = "/var/lib/xrdp/cert.pem";
    };

    environment.persistence."/persist".directories = ["/var/lib/xrdp"];

    services.xserver = {
      enable = true;
      autoRepeatDelay = 200;
      autoRepeatInterval = 35;
    };

    services.desktopManager.plasma6.enable = true;
    services.displayManager.sddm.enable = true;

    environment.etc = {
      "xdg/kdeglobals".text = ''
        [KScreen]
        ScaleFactor=2
        ScreenScaleFactors=rdp0=2;
      '';
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
      kdePackages.kinfocenter
      kdePackages.khelpcenter
      kdePackages.plasma-systemmonitor
      kdePackages.qrca
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

  flake.nixosModules.desktop-umbriel = {pkgs, ...}: {
    imports = [
      inputs.umbriel.nixosModules.default
      inputs.noctalia.nixosModules.default
    ];

    programs.umbriel.enable = true;
    programs.noctalia.enable = true;

    services.displayManager = {
      enable = true;
      sddm = {
        enable = true;
        wayland.enable = true;
      };
      autoLogin = {
        enable = true;
        user = "artur";
      };
    };

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };

    environment.systemPackages = with pkgs; [
      xwayland-satellite
      yazi
      wlr-randr
    ];

    home-manager.users.artur = {
      imports = [
        inputs.umbriel.homeModules.default
        inputs.noctalia.homeModules.default
      ];

      home.pointerCursor = {
        enable = true;
        package = pkgs.kdePackages.breeze;
        name = "breeze_cursors";
        size = 16;
      };

      programs.umbriel = {
        enable = true;
        settings = {
          general = {
            mod_key = "Alt";
            autostart = ["noctalia"];
          };
          output.Virtual-1.scale = 2;
          input = {
            focus.follows_mouse = true;
            touchpad.natural_scroll = true;
            mouse.natural_scroll = true;
          };
          keybinds = {
            "Mod+Return" = "spawn:alacritty";
            "Mod+Tab" = "scratchpad-focus-next";
            "Mod+Q" = "window-close";
            "Mod+D" = "spawn:noctalia msg panel-toggle launcher";
            "Mod+F" = "spawn:firefox";
            "Mod+E" = "spawn:emacs";
            "Mod+R" = "window-cycle-primary-extent";
            "Mod+Shift+R" = "window-cycle-primary-extent-back";
            "Mod+H" = "window-focus-left";
            "Mod+Shift+H" = "column-move-left";
            "Mod+J" = "window-focus-or-workspace-down";
            "Mod+Shift+J" = "window-move-down";
            "Mod+K" = "window-focus-or-workspace-up";
            "Mod+Shift+K" = "window-move-up";
            "Mod+L" = "window-focus-right";
            "Mod+Shift+L" = "column-move-right";
            "Mod+P" = "window-toggle-pinned";
            "Mod+M" = "window-toggle-maximize-to-edges";
            "Mod+0" = "overview-toggle";
            "Mod+1" = "workspace-switch:1";
            "Mod+2" = "workspace-switch:2";
            "Mod+3" = "workspace-switch:3";
            "Mod+4" = "workspace-switch:4";
            "Mod+5" = "workspace-switch:5";
            "Mod+6" = "workspace-switch:6";
            "Mod+7" = "workspace-switch:7";
            "Mod+8" = "workspace-switch:8";
            "Mod+9" = "workspace-switch:9";
            "Mod+Shift+1" = "window-move-to-workspace:1";
            "Mod+Shift+2" = "window-move-to-workspace:2";
            "Mod+Shift+3" = "window-move-to-workspace:3";
            "Mod+Shift+4" = "window-move-to-workspace:4";
            "Mod+Shift+5" = "window-move-to-workspace:5";
            "Mod+Shift+6" = "window-move-to-workspace:6";
            "Mod+Shift+7" = "window-move-to-workspace:7";
            "Mod+Shift+8" = "window-move-to-workspace:8";
            "Mod+Shift+9" = "window-move-to-workspace:9";
          };
        };
      };

      programs.noctalia = {
        enable = true;
        settings = {
          bar.default = {
            margin_ends = 2;
            start = ["workspaces"];
            center = ["active_window"];
            end = [
              "sysmon"
              "tray"
              "notifications"
              "clipboard"
              "network"
              "clock"
              "control-center"
              "session"
            ];
          };
          widget.network.show_label = false;
        };
      };
    };
  };
}

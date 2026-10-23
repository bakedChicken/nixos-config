# The development machines: artur's desktop and home configuration
{
  self,
  inputs,
  ...
}: {
  flake = {
    nixosModules = {
      workstation = {pkgs, ...}: {
        imports = [
          inputs.home-manager.nixosModules.default
        ];

        nixpkgs.config.allowUnfree = true;

        fonts.packages = with pkgs; [
          nerd-fonts.fira-code
        ];

        # Pushes kubernetes/platform to ghcr.io (nix run .#push-platform)
        age.secrets.ghcr-token = {
          rekeyFile = ../kubernetes/secrets/ghcr-token.age;
          owner = "artur";
          mode = "0400";
        };

        users.users.artur.extraGroups = [
          "video"
          "audio"
        ];
        environment.persistence."/persist".users.artur.directories = [
          "Documents"
          "Downloads"
          {
            directory = ".ssh";
            mode = "0700";
          }
          ".config/mozilla"
          ".local/share/direnv"
          ".local/state/bash"
        ];

        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.artur = {
          imports = [self.homeModules.artur];
          home = {
            username = "artur";
            homeDirectory = "/home/artur";
            stateVersion = "25.11";
            preferXdgDirectories = true;
          };
        };
      };

      # Plasma over xrdp (the Hyper-V machine)
      desktop-kde = {pkgs, ...}: {
        services.xrdp = {
          enable = true;
          openFirewall = true;
          audio.enable = true;
          defaultWindowManager = "startplasma-x11";
          # Generated on first start; /etc is read-only
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

        # Plasma's defaults for every user (home is erased on boot): 200% scale on xrdp's screen, a cursor
        # twice the default size (the default 24px, which Plasma doubles with the scale), no lock screen, and
        # no dimming, blanking or sleeping when idle
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

        # Apps Plasma brings outside its package list: the KDE PIM suite (KMail, Kontact, Merkuro,
        # Akonadi), the Orca screen reader and X's xterm
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

      # Umbriel with the Noctalia shell on a Wayland console (the UTM machine)
      desktop-umbriel = {pkgs, ...}: {
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

        home-manager.users.artur.imports = [self.homeModules.umbriel];
      };

      # Parked: GPU paravirtualisation for the Hyper-V machine (dxgkrnl and vgem built from Microsoft's WSL2 kernel tree)
      hyperv-gpu-pv = {
        config,
        lib,
        pkgs,
        ...
      }: let
        kernel = config.boot.kernelPackages.kernel;
        kernelModuleMakeFlags = config.boot.kernelPackages.kernelModuleMakeFlags;

        wsl2KernelSrc = pkgs.fetchgit {
          url = "https://github.com/microsoft/WSL2-Linux-Kernel.git";
          rev = "14794180686c2fb6307fbe359c359bec765249f3";
          sparseCheckout = [
            "drivers/hv/dxgkrnl"
            "drivers/gpu/drm/vgem"
            "include"
          ];
          hash = "sha256-+nvNsjXconUeu3KwOJqglqXClBcxp2ymBPmNYdBb+ik=";
        };

        buildOutOfTreeModule = {
          name,
          subdir,
          configVar,
          patches ? [],
          extraMakefile ? "",
        }:
          pkgs.stdenv.mkDerivation {
            pname = name;
            version = "6.18-${lib.substring 0 7 wsl2KernelSrc.rev}";
            src = wsl2KernelSrc;
            inherit patches;

            postPatch =
              ''
                sed -i 's/$(${configVar})/m/' ${subdir}/Makefile
              ''
              + lib.optionalString (extraMakefile != "") ''
                cat >> ${subdir}/Makefile <<"MAKEFILE_EOF"
                ${extraMakefile}
                MAKEFILE_EOF
              '';

            hardeningDisable = ["pic"];
            nativeBuildInputs = kernel.moduleBuildDependencies;
            makeFlags = kernelModuleMakeFlags;

            buildPhase = ''
              runHook preBuild
              make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
                M=$PWD/${subdir} \
                modules
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              install -D ${subdir}/${name}.ko \
                $out/lib/modules/${kernel.modDirVersion}/kernel/${subdir}/${name}.ko
              runHook postInstall
            '';

            meta = {
              license = lib.licenses.gpl2Only;
              platforms = ["x86_64-linux"];
            };
          };

        dxgkrnl = buildOutOfTreeModule {
          name = "dxgkrnl";
          subdir = "drivers/hv/dxgkrnl";
          configVar = "CONFIG_DXGKRNL";
          patches = [
            (pkgs.fetchpatch {
              name = "0001-Add-a-gpu-pv-support.patch";
              url = "https://content.staralt.dev/dxgkrnl-dkms/main/linux-msft-wsl-5.15.y/0001-Add-a-gpu-pv-support.patch";
              hash = "sha256-gsypOrRPrut6jWdH++ed2++E3M2uGfNt+oZrGtDgYm4=";
            })
          ];
          extraMakefile = ''
            ccflags-y += -I$(PWD)/include -D_MAIN_KERNEL_ -I${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include/linux -include ${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include/linux/vmalloc.h
          '';
        };

        vgem = buildOutOfTreeModule {
          name = "vgem";
          subdir = "drivers/gpu/drm/vgem";
          configVar = "CONFIG_DRM_VGEM";
        };
      in {
        boot.extraModulePackages = [
          dxgkrnl
          vgem
        ];
        boot.kernelModules = [
          "dxgkrnl"
          "vgem"
        ];

        services.udev.extraRules = ''
          KERNEL=="dxg", GROUP="video", MODE="0660"
        '';

        users.users.artur.extraGroups = [
          "video"
          "render"
        ];

        hardware.graphics.enable = true;

        systemd.tmpfiles.rules = [
          "d /usr/lib/wsl/lib 0755 root root -"
          "d /usr/lib/wsl/drivers 0755 root root -"
        ];

        environment.variables.LD_LIBRARY_PATH = ["/usr/lib/wsl/lib"];

        systemd.user.settings.Manager.DefaultEnvironment = "LD_LIBRARY_PATH=/usr/lib/wsl/lib";

        environment.systemPackages = with pkgs; [
          mesa-demos
          vulkan-tools
          libva-utils
          clinfo
        ];
      };
    };

    homeModules = {
      artur = {
        pkgs,
        config,
        ...
      }: {
        xdg.enable = true;
        systemd.user.startServices = "sd-switch";

        home.packages = with pkgs; [
          codex
          codex-acp
          claude-code
          claude-agent-acp
        ];

        programs.emacs = {
          enable = true;
          package = pkgs.emacs-pgtk;
          extraPackages = epkgs: [
            epkgs.treesit-grammars.with-all-grammars
            epkgs.tree-sitter-langs
            epkgs.nix-mode
            epkgs.nixfmt
            epkgs.vertico
            epkgs.marginalia
            epkgs.orderless
            epkgs.corfu
            epkgs.magit
            epkgs.diff-hl
            epkgs.envrc
            epkgs.ligature
            epkgs.company
            epkgs.toc-org
            epkgs.org-preview-html
            epkgs.agent-shell
          ];
          extraConfig = ''
            ;;; -*- lexical-binding: t -*-

            (org-babel-load-file
              (expand-file-name "early-init.org" user-emacs-directory))
            (org-babel-load-file
              (expand-file-name "config.org" user-emacs-directory))
          '';
        };

        xdg.configFile."emacs/early-init.org".source = ./emacs/early-init.org;
        xdg.configFile."emacs/config.org".source = ./emacs/config.org;

        programs.bash = {
          enable = true;
          historyControl = ["ignoredups"];
          historyFile = "${config.xdg.stateHome}/bash/history";
        };

        programs.git = {
          enable = true;
          settings.user = {
            name = "Artur Luppov";
            email = "artur.luppov@icloud.com";
          };
        };

        programs.firefox = {
          enable = true;
          configPath = "${config.xdg.configHome}/mozilla/firefox";
        };

        programs.alacritty = {
          enable = true;
          settings = {
            general.import = ["themes/noctalia.toml"];
            font = {
              normal = {
                family = "FiraCode Nerd Font";
                style = "Regular";
              };
            };
          };
        };

        programs.direnv.enable = true;
        programs.starship = {
          enable = true;
          enableBashIntegration = true;
          settings = {
            hostname.ssh_only = false;
            username.show_always = true;
          };
        };

        programs.eza = {
          enable = true;
          enableBashIntegration = true;
          colors = "always";
          git = true;
          icons = "always";
          extraOptions = [
            "--group-directories-first"
            "--header"
          ];
        };

        programs.fzf = {
          enable = true;
          enableBashIntegration = true;
        };
      };

      umbriel = {pkgs, ...}: {
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
            output = {
              Virtual-1 = {
                scale = 2;
              };
            };
            input = {
              focus = {
                follows_mouse = true;
              };
              touchpad = {
                natural_scroll = true;
              };
              mouse = {
                natural_scroll = true;
              };
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
            widget = {
              network = {
                show_label = false;
              };
            };
          };
        };
      };
    };
  };
}

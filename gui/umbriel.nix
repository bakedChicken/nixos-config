{ inputs, ... }:
{
  flake = {
    homeModules = {
      umbriel = {
        imports = [
          inputs.umbriel.homeModules.default
        ];

        programs.umbriel = {
          enable = true;
          settings = {
            general = {
              mod_key = "Alt";
              autostart = [ "noctalia" ];
            };
            output = {
              Virtual-1 = {
                mode = "3024x1890@60";
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
              "Mod+R" = "window-cycle-width";
              "Mod+Shift+R" = "window-cycle-width-back";
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
      };
    };

    nixosModules = {
      umbriel = { pkgs, ... }: {
        imports = [
          inputs.umbriel.nixosModules.default
        ];

        programs.umbriel.enable = true;
        environment.systemPackages = with pkgs; [
          xwayland-satellite
          wlr-randr
        ];

        home-manager.users.artur.imports = [
          inputs.self.homeModules.umbriel
        ];
      };
    };
  };
}

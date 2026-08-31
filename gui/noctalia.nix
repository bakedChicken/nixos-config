{ inputs, ... }:
{
  flake = {
    homeModules = {
      noctalia = {
        imports = [
          inputs.noctalia.homeModules.default
        ];

        programs.noctalia = {
          enable = true;
          settings = {
            bar.default = {
              margin_ends = 2;
              start = [ "workspaces" ];
              center = [ "active_window" ];
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

    nixosModules = {
      noctalia = {
        imports = [
          inputs.noctalia.nixosModules.default
        ];

        programs.noctalia.enable = true;
        home-manager.users.artur.imports = [
          inputs.self.homeModules.noctalia
        ];
      };
    };
  };
}

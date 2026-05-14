{ ... }:
{
  flake = {
    homeModules.artur =
      { config, pkgs, ... }:
      {
        xdg.enable = true;
        systemd.user.startServices = "sd-switch";

        programs.bash = {
          enable = true;
          historyControl = [ "ignoredups" ];
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

        programs.alacritty.enable = true;

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

        programs.nvf = {
          enable = true;
          settings = {
            vim.lsp = {
              enable = true;
              formatOnSave = true;
              inlayHints.enable = true;
            };
            vim.theme = {
              enable = true;
              name = "catppuccin";
              style = "auto";
            };
            vim.visuals.indent-blankline.enable = true;
            vim.visuals.nvim-cursorline.enable = true;
            vim.visuals.rainbow-delimiters.enable = true;
            vim.statusline.lualine.enable = true;
            vim.languages.nix.enable = true;
            vim.autocomplete.blink-cmp.enable = true;
            vim.git.enable = true;
            vim.autopairs.nvim-autopairs.enable = true;
          };
        };
      };

    nixosModules.artur =
      { pkgs, ... }:
      {
        users.users.artur = {
          description = "Artur Luppov";
          isNormalUser = true;
          extraGroups = [
            "wheel"
            "video"
            "audio"
            "networkmanager"
          ];
          hashedPassword = "$6$Uk57TgLuIsocbW6m$Y1Ljj7fP4/m5dMQkMFa2Nrs0hUDcF.62qONruluGtIDS8LtLog7SAuYU7dbOMexLyJX0z7YohILhCToUt8hHa0";
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHDUMJQzDn3WbH69QhZVvej8JpCn6b6jUi4ZpHU952sG artur"
          ];
          shell = pkgs.bash;
        };
      };
  };
}

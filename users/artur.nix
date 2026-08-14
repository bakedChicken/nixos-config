{ ... }:
{
  flake = {
    homeModules.artur =
      { pkgs, config, ... }:
      {
        xdg.enable = true;
        systemd.user.startServices = "sd-switch";

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
            epkgs.doom-themes
          ];
          extraConfig = ''
            (org-babel-load-file
              (expand-file-name "early-init.org" user-emacs-directory))
            (org-babel-load-file
              (expand-file-name "config.org" user-emacs-directory))
          '';
        };

        xdg.configFile."emacs/early-init.org".source = ./configs/emacs/early-init.org;
        xdg.configFile."emacs/config.org".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Documents/nixos-config/users/configs/emacs/config.org";

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

        programs.alacritty = {
          enable = true;
          settings = {
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
            vim.languages.go.enable = true;
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
            # Public key of the main workstation
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII2jPT/9sf897gTeV7skAMZe6a2vMaLXMwdp1QQDvbt4"
            # Public key of the laptop
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCxojjMerhqRDdte4XWui7vOW5BmiTp4XM7ibgvYVvf2CPCFTlQUvFKk2GmvUvuEPWpKoQJi9eZ3W+r0JHGHMFc3FwGOC8PUGqO/fMFt0WfcAgXzS0whsxOmOqKWDCqRn71T8RqzjkMPEKB0+t1wLE5ikkDCmYuKxH3gM7oOwluE6V27Oq15dCU3JYjopwu0dVmqrgT7oYQfCTWgztQWuBlKQg/3PAICoxsyzjufbplxKX0GZ1lRdMIenGIvVFMs/nHvlVCcwGMYkBeq6A1DJZy5RUO/tUNWcH9NFD3MdL8Iboo6Gj9DAiuZWFr7mTRgq+cOA3FP97UrPgl58xEJ9bj"
          ];
          shell = pkgs.bash;
        };
      };
  };
}

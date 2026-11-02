{self, ...}: {
  flake.nixosModules.artur = {pkgs, ...}: {
    users.users.artur = {
      description = "Artur Luppov";
      isNormalUser = true;
      uid = 1000;
      group = "artur";
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
      hashedPassword = "$6$Uk57TgLuIsocbW6m$Y1Ljj7fP4/m5dMQkMFa2Nrs0hUDcF.62qONruluGtIDS8LtLog7SAuYU7dbOMexLyJX0z7YohILhCToUt8hHa0";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII2jPT/9sf897gTeV7skAMZe6a2vMaLXMwdp1QQDvbt4"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPq58/Uy+EmKE+b4RveIsfUffQ+nHpW+D6rg2b70l3mS"
      ];
      shell = pkgs.bash;
    };
    users.groups.artur.gid = 1000;
  };

  flake.nixosModules.artur-workstation = {pkgs, ...}: {
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

    home-manager.users.artur = {config, ...}: {
      imports = [self.homeModules.artur];

      programs.emacs.package = pkgs.emacs-pgtk;

      programs.firefox = {
        enable = true;
        configPath = "${config.xdg.configHome}/mozilla/firefox";
      };
    };
  };

  flake.homeModules.artur = {
    pkgs,
    config,
    ...
  }: {
    home.stateVersion = "25.11";
    home.preferXdgDirectories = true;
    xdg.enable = true;

    home.packages = with pkgs; [
      claude-code
      claude-agent-acp
      ripgrep
      fd
      freerdp
    ];

    programs.alacritty = {
      enable = true;
      settings.font.normal = {
        family = "FiraCode Nerd Font";
        style = "Regular";
      };
    };

    programs.emacs = {
      enable = true;
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
        epkgs.evil
        epkgs.diff-hl
        epkgs.envrc
        epkgs.ligature
        epkgs.toc-org
        epkgs.tabspaces
        epkgs.consult
        epkgs.consult-eglot
        epkgs.embark
        epkgs.embark-consult
        epkgs.wgrep
        epkgs.breadcrumb
        epkgs.nerd-icons-dired
        epkgs.org-preview-html
        epkgs.agent-shell
      ];
      extraConfig = ''
        ;;; -*- lexical-binding: t -*-

        (dolist (name '("early-init" "config"))
          (let* ((org (expand-file-name (concat name ".org") user-emacs-directory))
                 (el (expand-file-name (format "%s-%s.el" name (md5 (file-truename org))) user-emacs-directory)))
            (unless (file-exists-p el)
              (require 'ob-tangle)
              (org-babel-tangle-file org el "emacs-lisp"))
            (load el)))
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
      settings = {
        user = {
          name = "Artur Luppov";
          email = "artur.luppov@icloud.com";
        };
        core.autocrlf = "input";
        pull.rebase = true;
      };
    };

    programs.direnv.enable = true;
    programs.starship = {
      enable = true;
      settings = {
        hostname.ssh_only = false;
        username.show_always = true;
      };
    };
    programs.eza = {
      enable = true;
      colors = "always";
      git = true;
      icons = "always";
      extraOptions = [
        "--group-directories-first"
        "--header"
      ];
    };
    programs.fzf.enable = true;
    programs.nh.enable = true;
  };
}

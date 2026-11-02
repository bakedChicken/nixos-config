{
  flake.nixosModules.builder = {
    config,
    pkgs,
    ...
  }: {
    nix.daemonCPUSchedPolicy = "idle";
    nix.daemonIOSchedClass = "idle";

    environment.systemPackages = [pkgs.gitMinimal];
    nix.settings.build-dir = "/nix/var/nix/builds";
    systemd.tmpfiles.rules = ["d /nix/var/nix/builds 0755 root root 7d"];

    # Serves this store as the binary cache every other host asks before building
    age.secrets.binary-cache-key.rekeyFile = ../kubernetes/secrets/binary-cache-key.age;
    services.harmonia.cache = {
      enable = true;
      signKeyPaths = [config.age.secrets.binary-cache-key.path];
    };
    networking.firewall.allowedTCPPorts = [5000];
  };

  flake.darwinModules.builder = {
    nix.linux-builder = {
      enable = true;
      ephemeral = true;
      maxJobs = 8;
      config.virtualisation = {
        cores = 8;
        darwin-builder = {
          memorySize = 16384;
          diskSize = 102400;
        };
      };
    };

    nix.buildMachines = [
      {
        hostName = "storage-station.local";
        sshUser = "artur";
        sshKey = "/Users/yoba/.ssh/id_ed25519";
        systems = ["x86_64-linux"];
        maxJobs = 4;
        supportedFeatures = ["big-parallel" "kvm" "nixos-test"];
      }
    ];

    programs.ssh.knownHosts.storage-station = {
      hostNames = ["storage-station.local"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPGl/IHpSEQ7w4By0Rbzeik857lXvoj+zK+XYCOQsOwf";
    };
  };
}

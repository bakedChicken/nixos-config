{
  self,
  config,
  ...
}: let
  developmentEnvironment = self.nixosConfigurations.nixos-development-environment.config;
in {
  flake.nixosModules.builder = {
    config,
    pkgs,
    ...
  }: {
    nix.daemonCPUSchedPolicy = "idle";
    nix.daemonIOSchedClass = "idle";

    environment.systemPackages = [pkgs.gitMinimal];

    age.secrets.binary-cache-key.rekeyFile = ../kubernetes/secrets/binary-cache-key.age;
    services.harmonia.cache = {
      enable = true;
      signKeyPaths = [config.age.secrets.binary-cache-key.path];
    };
    networking.firewall.allowedTCPPorts = [5000];
  };

  flake.darwinModules.builder = {
    nix.buildMachines = [
      {
        hostName = developmentEnvironment.networking.fqdn;
        sshUser = "artur";
        sshKey = "/Users/yoba/.ssh/id_ed25519";
        systems = ["x86_64-linux"];
        maxJobs = 4;
        supportedFeatures = ["big-parallel" "kvm" "nixos-test"];
      }
    ];

    programs.ssh.knownHosts.storage-station = {
      hostNames = [self.nixosConfigurations.storage-station.config.networking.fqdn];
      publicKey = config.kubernetes.clusters.edge.nodes.storage-station.hostPubkey;
    };
    programs.ssh.knownHosts.nixos-development-environment = {
      hostNames = [developmentEnvironment.networking.fqdn];
      publicKey = developmentEnvironment.age.rekey.hostPubkey;
    };
  };
}

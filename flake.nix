{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";

    nixos-raspberry-pi-uefi = {
      url = "github:bakedChicken/nixos-raspberry-pi-uefi";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    umbriel = {
      url = "git+https://github.com/noctalia-dev/umbriel";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix-rekey = {
      url = "github:oddlama/agenix-rekey";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    lintel.url = "git+ssh://git@github.com/bakedChicken/lintel";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    treefmt-nix,
    home-manager,
    flake-parts,
    disko,
    agenix,
    agenix-rekey,
    impermanence,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} (
      {withSystem, ...}: {
        imports = [
          treefmt-nix.flakeModule
          home-manager.flakeModules.home-manager
          agenix-rekey.flakeModules.default
          ./workstation
          ./kubernetes
        ];

        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];

        perSystem = {
          pkgs,
          inputs',
          ...
        }: {
          treefmt = {
            projectRootFile = "flake.nix";
            programs.prettier.enable = true;
            programs.alejandra.enable = true;
          };

          devShells.default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              inputs'.deploy-rs.packages.default
              inputs'.agenix-rekey.packages.default
              nixd
            ];
          };
        };

        flake = {
          nixosModules = {
            # What every machine has
            base = {
              config,
              lib,
              pkgs,
              ...
            }: {
              imports = [
                agenix.nixosModules.default
                agenix-rekey.nixosModules.default
                impermanence.nixosModules.impermanence
              ];

              nix = {
                settings = {
                  experimental-features = [
                    "nix-command"
                    "flakes"
                  ];
                  trusted-users = [
                    "root"
                    "@wheel"
                  ];
                };
                channel.enable = false;
                optimise.automatic = true;
                gc = {
                  automatic = true;
                  options = "--delete-older-than 30d";
                };
              };
              boot.loader.systemd-boot.configurationLimit = 10;

              boot.kernelPackages = pkgs.linuxPackages_latest;

              # Swap in compressed memory, not on disk: swap on a ZFS zvol can deadlock, and the SD cards would wear
              zramSwap.enable = true;

              # One address per family per machine, the same after a reinstall: DHCP reservations by MAC, EUI-64, no
              # privacy addresses. CLAT and the IPv6-only DHCP option, so a machine works on an IPv6-only network too.
              networking.useDHCP = false;
              networking.networkmanager = {
                enable = true;
                settings.connection = {
                  "ipv4.dhcp-client-id" = "mac";
                  "ipv4.dhcp-ipv6-only-preferred" = 2;
                  "ipv4.clat" = 1;
                  "ipv6.addr-gen-mode" = 0;
                  "ipv6.ip6-privacy" = 0;
                  "ipv6.dhcp-duid" = "ll";
                };
              };
              # NetworkManager enables wpa_supplicant for Wi-Fi; no machine has any
              networking.wireless.enable = lib.mkForce false;

              services.avahi = {
                enable = true;
                nssmdns4 = true;
                nssmdns6 = true;
                publish = {
                  enable = true;
                  userServices = true;
                  domain = true;
                };
              };
              # systemd would create /etc/avahi/services for the daemon, which fails on a read-only /etc
              systemd.services.avahi-daemon.serviceConfig.ConfigurationDirectory = lib.mkForce "";
              # resolved owns resolv.conf (/etc is read-only on most machines); avahi alone answers mDNS: resolved
              # takes its own name repeated back by the router for a conflict and renames itself endlessly
              services.resolved = {
                enable = true;
                settings.Resolve = {
                  MulticastDNS = false;
                  LLMNR = false;
                };
              };

              age.rekey = {
                storageMode = "local";
                localStorageDir = ./. + "/rekeyed/${config.networking.hostName}";
                masterIdentities = ["/home/artur/.ssh/id_ed25519"];
              };

              services.openssh = {
                enable = true;
                authorizedKeysInHomedir = false;
                hostKeys = lib.mkDefault [
                  {
                    path = "/etc/ssh/ssh_host_ed25519_key";
                    type = "ed25519";
                  }
                ];
              };
              security.sudo.wheelNeedsPassword = false;

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

              # Nobody sits at a console: emergency mode would only stop sshd and wait forever
              systemd.enableEmergencyMode = false;

              time.timeZone = "Europe/Vienna";
              documentation.enable = false;
              documentation.nixos.enable = false;
              system.stateVersion = "25.11";
            };

            # Nothing undeclared survives a reboot: / is a tmpfs and /etc a read-only overlay; what the machine owns
            # (system state, logs, host keys, machine ID) lives on /persist
            ephemeral = {
              fileSystems."/" = {
                device = "none";
                fsType = "tmpfs";
                options = [
                  "defaults"
                  "size=25%"
                  "mode=755"
                ];
              };
              fileSystems."/persist".neededForBoot = true;

              boot.loader.systemd-boot.enable = true;
              boot.loader.efi.canTouchEfiVariables = true;

              system.etc.overlay.enable = true;
              system.etc.overlay.mutable = false;
              services.userborn.enable = true;
              users.mutableUsers = false;

              environment.persistence."/persist" = {
                hideMounts = true;
                directories = [
                  "/var/lib/nixos"
                  "/var/lib/systemd"
                  "/var/lib/NetworkManager"
                  "/var/log"
                ];
              };

              services.openssh.hostKeys = [
                {
                  path = "/persist/etc/ssh/ssh_host_ed25519_key";
                  type = "ed25519";
                }
              ];
              age.identityPaths = ["/persist/etc/ssh/ssh_host_ed25519_key"];
              environment.etc."machine-id".source = "/persist/etc/machine-id";
              systemd.tmpfiles.rules = [
                "d /persist 0755 root root - -"
                "d /persist/etc 0755 root root - -"
              ];
            };

            # The one disk layout: the ESP and a btrfs with /nix and /persist (/ is the tmpfs of ephemeral)
            disk = {lib, ...}: {
              imports = [disko.nixosModules.default];

              disko.devices.disk.main = {
                type = "disk";
                device = lib.mkDefault "/dev/sda";
                content = {
                  type = "gpt";
                  partitions = {
                    ESP = {
                      priority = 1;
                      name = "ESP";
                      start = "1M";
                      end = "512M";
                      type = "EF00";
                      content = {
                        type = "filesystem";
                        format = "vfat";
                        mountpoint = "/boot";
                        mountOptions = ["umask=0077"];
                      };
                    };
                    root = {
                      size = "100%";
                      content = {
                        type = "btrfs";
                        extraArgs = ["-f"];
                        subvolumes = {
                          "/nix" = {
                            mountpoint = "/nix";
                            mountOptions = [
                              "compress=zstd"
                              "noatime"
                            ];
                          };
                          "/persist" = {
                            mountpoint = "/persist";
                            mountOptions = [
                              "compress=zstd"
                              "noatime"
                            ];
                          };
                        };
                      };
                    };
                  };
                };
              };
            };

            hyperv-vm = {
              virtualisation.hypervGuest.enable = true;
            };

            raspberry-pi-3 = {modulesPath, ...}: {
              imports = [
                "${modulesPath}/profiles/minimal.nix"
                inputs.nixos-raspberry-pi-uefi.nixosModules.default
              ];

              hardware.pi3.uefi.enable = true;
              boot.loader.systemd-boot.enable = true;
              fileSystems."/".fsType = "btrfs";

              services.journald.settings.Journal = {
                Storage = "volatile";
                RuntimeMaxUse = "16M";
              };
            };
          };

          nixosConfigurations = {
            nixos-development-environment-aarch64 = withSystem "aarch64-linux" (
              {system, ...}:
                nixpkgs.lib.nixosSystem {
                  modules = [
                    self.nixosModules.base
                    self.nixosModules.ephemeral
                    self.nixosModules.disk
                    self.nixosModules.workstation
                    self.nixosModules.desktop-umbriel
                    {
                      networking.hostName = "nixos-development-environment-aarch64";
                      nixpkgs.hostPlatform = system;
                      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDD0wl0FAPfCFuE13ul8D+5D1Zq4vrWQsRVF28aZgcgN";
                    }
                  ];
                }
            );

            nixos-development-environment = withSystem "x86_64-linux" (
              {system, ...}:
                nixpkgs.lib.nixosSystem {
                  modules = [
                    self.nixosModules.base
                    self.nixosModules.ephemeral
                    self.nixosModules.disk
                    self.nixosModules.hyperv-vm
                    self.nixosModules.workstation
                    self.nixosModules.desktop-kde
                    {
                      networking.hostName = "nixos-development-environment";
                      nixpkgs.hostPlatform = system;
                      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMqP+nJMz3zHwDHZOfCNHDNgLhSqvjs5tgbxYVs6eu4X";
                      # Builds the Raspberry Pis' systems
                      boot.binfmt.emulatedSystems = ["aarch64-linux"];
                    }
                  ];
                }
            );

            # The storage server: ZFS pools behind SMB, iSCSI for both clusters, the media apps and the edge cluster's
            # server. AMD Ryzen Embedded V1500B board, no console. Its services are in storage-station.nix.
            storage-station = withSystem "x86_64-linux" (
              {system, ...}:
                nixpkgs.lib.nixosSystem {
                  modules = [
                    self.nixosModules.base
                    self.nixosModules.ephemeral
                    self.nixosModules.storage-server
                    inputs.lintel.nixosModules.default
                    ./storage-station.nix
                    ({pkgs, ...}: {
                      networking.hostName = "storage-station";
                      containers.edge-server.path = self.nixosConfigurations.k8s-node-x86-64-1.config.system.build.toplevel;
                      nixpkgs.hostPlatform = system;
                      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPGl/IHpSEQ7w4By0Rbzeik857lXvoj+zK+XYCOQsOwf";

                      boot.kernelParams = [
                        "console=tty0"
                        "console=ttyS0,115200"
                      ];
                      boot.initrd.availableKernelModules = [
                        "ahci"
                        "xhci_pci"
                        "usb_storage"
                        "uas"
                        "sd_mod"
                      ];
                      hardware.enableRedistributableFirmware = true;
                      hardware.cpu.amd.updateMicrocode = true;
                      # The board's watchdog: a hung system resets itself instead of waiting for someone at a console
                      boot.kernelModules = ["sp5100_tco"];
                      systemd.settings.Manager = {
                        RuntimeWatchdogSec = "30s";
                        RebootWatchdogSec = "10min";
                      };

                      # systemd-boot on the internal USB module, next to SystemRescue, which the firmware can also
                      # start on its own as the second boot entry
                      boot.loader.systemd-boot.extraEntries."systemrescue.conf" = ''
                        title SystemRescue 13.02
                        linux /sysresccd/boot/x86_64/vmlinuz
                        initrd /sysresccd/boot/x86_64/sysresccd.img
                        options archisobasedir=sysresccd archisolabel=RESCUE1302
                      '';
                      fileSystems = {
                        "/boot" = {
                          device = "/dev/disk/by-id/usb-_USB_DISK_MODULE_19001154C7B52558-0:0-part1";
                          fsType = "vfat";
                          options = ["umask=0077"];
                        };
                        "/nix" = {
                          device = "tank/system/nix";
                          fsType = "zfs";
                          neededForBoot = true;
                        };
                        "/persist" = {
                          device = "tank/system/persist";
                          fsType = "zfs";
                        };
                        # The pools themselves aren't mounted. nofail: a mount that hangs (ZFS under load) must not
                        # fail local-fs.target; the services that use one require it instead.
                        "/home" = {
                          device = "tank/home";
                          fsType = "zfs";
                          options = ["nofail"];
                        };
                        "/home/artur" = {
                          device = "tank/home/artur";
                          fsType = "zfs";
                          options = ["nofail"];
                        };
                        "/srv/media" = {
                          device = "dozer/media";
                          fsType = "zfs";
                          options = ["nofail"];
                        };
                        "/srv/3d-models" = {
                          device = "dozer/data/3d-models";
                          fsType = "zfs";
                          options = ["nofail"];
                        };
                        "/srv/time-machine" = {
                          device = "dozer/backups/time-machine";
                          fsType = "zfs";
                          options = ["nofail"];
                        };
                        "/srv/vm-archive" = {
                          device = "dozer/backups/vm-archive";
                          fsType = "zfs";
                          options = ["nofail"];
                        };
                      };

                      boot.supportedFilesystems.zfs = true;
                      boot.zfs.forceImportRoot = false;
                      boot.zfs.extraPools = ["dozer"];
                      # The host ID the pools were created with; the pools refuse to import under another one
                      networking.hostId = "7bbabf8f";

                      services.zfs.autoScrub = {
                        enable = true;
                        interval = "monthly";
                      };
                      services.smartd = {
                        enable = true;
                        # Self-tests: short daily at 02:00, long on the 15th at 04:00 (the scrub runs on the 1st).
                        # Results show in the smartctl exporter and Glance.
                        defaults.autodetected = "-a -o on -s (S/../.././02|L/../15/./04)";
                      };
                      services.sanoid = {
                        enable = true;
                        templates = {
                          production = {
                            hourly = 24;
                            daily = 14;
                            monthly = 3;
                          };
                          media = {
                            hourly = 0;
                            daily = 7;
                            monthly = 0;
                          };
                        };
                        datasets = {
                          "tank/kubernetes" = {
                            useTemplate = ["production"];
                            recursive = true;
                          };
                          "tank/kubernetes-edge" = {
                            useTemplate = ["production"];
                            recursive = true;
                          };
                          "tank/home" = {
                            useTemplate = ["production"];
                            recursive = true;
                          };
                          "tank/edge-server" = {
                            useTemplate = ["production"];
                          };
                          "tank/apps" = {
                            useTemplate = ["production"];
                            recursive = true;
                          };
                          "dozer/data" = {
                            useTemplate = ["production"];
                            recursive = true;
                          };
                          "dozer/backups" = {
                            useTemplate = ["production"];
                            recursive = true;
                          };
                          "dozer/media" = {
                            useTemplate = ["media"];
                            recursive = true;
                          };
                        };
                      };

                      environment.persistence."/persist".directories = [
                        "/var/lib/samba"
                        "/var/lib/target"
                        "/var/lib/containers"
                        {
                          directory = "/var/lib/private";
                          mode = "0700";
                        }
                      ];

                      # Rebuilds also run on the box itself, from the checkout in artur's home
                      environment.systemPackages = [pkgs.gitMinimal];
                      nix.settings.build-dir = "/nix/var/nix/builds";
                      systemd.tmpfiles.rules = ["d /nix/var/nix/builds 0755 root root 7d"];

                      users.users.artur = {
                        extraGroups = [
                          "designers"
                          "apps"
                        ];
                      };
                      users.users.tatyana = {
                        uid = 1001;
                        description = "Tatyana Luppova";
                        isNormalUser = true;
                        group = "tatyana";
                        extraGroups = ["designers"];
                        home = "/var/empty";
                        createHome = false;
                        shell = pkgs.shadow;
                        hashedPassword = "!";
                      };
                      users.users.apps = {
                        uid = 568;
                        group = "apps";
                        isSystemUser = true;
                      };
                      users.groups = {
                        tatyana.gid = 1001;
                        designers.gid = 1002;
                        apps.gid = 568;
                      };

                      # Two bridges: br0 on the 10G port is the home network, br33 carries VLAN 33 (the clusters) and
                      # bridges the edge server and the Raspberry Pis on the 2.5G ports onto it. No automatic "Wired
                      # connection N": it would take the ports before their own profiles do.
                      networking.networkmanager.settings.main.no-auto-default = "*";
                      networking.networkmanager.ensureProfiles.profiles = {
                        br0 = {
                          connection = {
                            id = "br0";
                            type = "bridge";
                            interface-name = "br0";
                          };
                          bridge.stp = false;
                          ipv4.method = "auto";
                          ipv6.method = "auto";
                        };
                        br0-enp5s0 = {
                          connection = {
                            id = "br0-enp5s0";
                            type = "ethernet";
                            interface-name = "enp5s0";
                            controller = "br0";
                            port-type = "bridge";
                          };
                        };
                        br33 = {
                          connection = {
                            id = "br33";
                            type = "bridge";
                            interface-name = "br33";
                          };
                          bridge.stp = false;
                          ipv4 = {
                            method = "auto";
                            never-default = true;
                          };
                          ipv6 = {
                            method = "auto";
                            never-default = true;
                          };
                        };
                        br33-vlan33 = {
                          connection = {
                            id = "br33-vlan33";
                            type = "vlan";
                            interface-name = "vlan33";
                            controller = "br33";
                            port-type = "bridge";
                          };
                          vlan = {
                            parent = "enp5s0";
                            id = 33;
                          };
                        };
                        br33-enp6s0 = {
                          connection = {
                            id = "br33-enp6s0";
                            type = "ethernet";
                            interface-name = "enp6s0";
                            controller = "br33";
                            port-type = "bridge";
                          };
                        };
                        br33-enp7s0 = {
                          connection = {
                            id = "br33-enp7s0";
                            type = "ethernet";
                            interface-name = "enp7s0";
                            controller = "br33";
                            port-type = "bridge";
                          };
                        };
                      };
                    })
                  ];
                }
            );
          };

          deploy.nodes.storage-station = {
            hostname = "storage-station.local";
            sshUser = "artur";
            profiles.system = {
              user = "root";
              path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.storage-station;
            };
          };
        };

        kubernetes.clusters = {
          main = {
            domain = "burned.host";
            internalDomain = "internal.k8s.burned.host";
            init = "k8s-node-2";
            tokenFile = ./kubernetes/secrets/join-token.age;
            loadBalancerPool = [
              {cidr = "172.16.33.200/32";}
            ];
            storage.dataset = "tank/kubernetes";
            storage.csiDriverConfig = ./kubernetes/secrets/democratic-csi-config-main.age;
            modules = with self.nixosModules; [
              cilium
              kube-vip
              openbao
              argocd
            ];
            nodes = {
              k8s-node-1 = {
                role = "server";
                system = "x86_64-linux";
                hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBgayw+LEcOM0N62lRmY67rwsut5AlQzH7s30qi1/uKE";
                modules = with self.nixosModules; [
                  hyperv-vm
                  disk
                  ephemeral
                ];
              };
              k8s-node-2 = {
                role = "server";
                system = "x86_64-linux";
                hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILg/ncWfxWXZX4oLFq13dgzcNoOyurb+fkicj4E4G9MC";
                modules = with self.nixosModules; [
                  hyperv-vm
                  disk
                  ephemeral
                ];
              };
              k8s-node-3 = {
                role = "server";
                system = "x86_64-linux";
                hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICsEqPnBF3JpXgFLVa37SjdKyiOBAbrj1KDtb9dSH/44";
                modules = with self.nixosModules; [
                  hyperv-vm
                  disk
                  ephemeral
                ];
              };
            };
          };

          edge = {
            domain = "edge.burned.host";
            internalDomain = "internal.edge.burned.host";
            init = "k8s-node-x86-64-1";
            tokenFile = ./kubernetes/secrets/edge-join-token.age;
            storage.dataset = "tank/kubernetes-edge";
            storage.csiDriverConfig = ./kubernetes/secrets/democratic-csi-config-edge.age;
            ca = {
              cert = ./kubernetes/secrets/edge-ca-crt.age;
              key = ./kubernetes/secrets/edge-ca-key.age;
            };
            modules = with self.nixosModules; [
              flannel
              argocd-spoke
              mktxp
            ];
            nodes = {
              # The NixOS container edge-server on storage-station, rebuilt with it (see storage-station.nix)
              k8s-node-x86-64-1 = {
                role = "server";
                deploy = false;
                system = "x86_64-linux";
                hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDvQMlh94ENInyK8lViex3F7PFkaICrpvf3Xr5E0/Hx3";
                modules = [
                  ({lib, ...}: {
                    boot.isContainer = true;
                    users.mutableUsers = false;
                    # The container runs resolved like every other machine, not the host's resolv.conf
                    networking.useHostResolvConf = false;
                    # NetworkManager only manages links udev has initialised, and there's no udev in a container;
                    # networkd configures container links itself
                    networking.networkmanager.enable = lib.mkForce false;
                    networking.useNetworkd = true;
                    systemd.network.networks."10-eth0" = {
                      matchConfig.Name = "eth0";
                      networkConfig = {
                        DHCP = "ipv4";
                        IPv6AcceptRA = true;
                      };
                      dhcpV4Config.ClientIdentifier = "mac";
                    };
                  })
                ];
              };
              k8s-node-aarch64-1 = {
                role = "agent";
                system = "aarch64-linux";
                hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID0s5TvAii/foOw3yNLcvHURHZPL+j4p1HwvbgP3ea1X";
                modules = [self.nixosModules.raspberry-pi-3];
              };
              k8s-node-aarch64-2 = {
                role = "agent";
                system = "aarch64-linux";
                hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJK6Befn24tvAQ9f+nPX3giRZB2mVfggSX2CCdhnE4Ss";
                modules = [self.nixosModules.raspberry-pi-3];
              };
            };
          };
        };
      }
    );
}

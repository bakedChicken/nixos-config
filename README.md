# NixOS configuration

## Kubernetes cluster

Create 3 Hyper-V Virtual Machines with the following configuration:

* CPU: 32
* RAM: 16384 MB
* Host Network

Boot NixOS live image on each Hyper-V VM.

The default linux user on live image is `nixos`. We need to set up a password for that user using `passwd`.

After setting up the password, execute the following nixos-anywhere commands:

```sh
nix run github:nix-community/nixos-anywhere -- --flake .#k8s-node-1 --target-host nixos@<IP-1>
nix run github:nix-community/nixos-anywhere -- --flake .#k8s-node-2 --target-host nixos@<IP-2>
nix run github:nix-community/nixos-anywhere -- --flake .#k8s-node-3 --target-host nixos@<IP-3>
```

After that all VMs should reboot.

Connect to each VM using ssh: `ssh k8s-node-1.local`. It should let you in without a password, because authorized_keys were provided in the NixOS configuration.

Get the generated public ssh host keys: `cat /etc/ssh/ssh_host_ed25519_key.pub` and paste it into the NixOS configuration for agenix secrets.

Rekey secrets using `agenix rekey -a`.

Redeploy changes using either `nixos-rebuild` or `deploy-rs`:

```sh
sudo nixos-rebuild switch --flake .#k8s-node-1 --target-host artur@k8s-node-1.local --elevate=sudo --ask-elevate-password
sudo nixos-rebuild switch --flake .#k8s-node-2 --target-host artur@k8s-node-2.local --elevate=sudo --ask-elevate-password
sudo nixos-rebuild switch --flake .#k8s-node-3 --target-host artur@k8s-node-3.local --elevate=sudo --ask-elevate-password
```

OR

```sh
deploy .
```

Done.

## Kubernetes resources

I want to introduce basic cluster resources that should be configured via NixOS, because they either require OS-level configurations (network, storage) or they are neccessary for cluster to operate normally.

I'm going to track the service list here:

* kube-vip
* truenas-scale-csi provisioner
* certbot
* flux
* gateway-api
* cillium


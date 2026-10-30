{
  flake.nixosModules.hyperv-vm = {
    virtualisation.hypervGuest.enable = true;
  };
}

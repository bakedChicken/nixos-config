{
  flake.nixosModules.sunshine = {
    services.sunshine.enable = true;
    services.sunshine.capSysAdmin = true;
    services.sunshine.openFirewall = true;
    hardware.uinput.enable = true;
  };
}

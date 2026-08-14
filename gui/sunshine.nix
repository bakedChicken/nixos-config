{
  flake.nixosModules.sunshine = {
    services.sunshine.enable = true;
    services.sunshine.autoStart = true;
    services.sunshine.capSysAdmin = true;
    services.sunshine.openFirewall = true;
    hardware.uinput.enable = true;

    users.users.artur.extraGroups = [ "uinput" ];
  };
}

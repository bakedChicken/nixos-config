{
  flake.nixosModules.sunshine = {
    services.sunshine.enable = true;
    services.sunshine.autoStart = true;
    services.sunshine.capSysAdmin = true;
    services.sunshine.openFirewall = true;
    hardware.uinput.enable = true;

    users.users.artur.extraGroups = [ "uinput" ];

    # Since sunshine cannot start without logging in
    # services.displayManager.autoLogin = {
    #  enable = true;
    #  user = "artur";
    # };
  };
}

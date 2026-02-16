{ ... }:
{
  flake.nixosModules.xrdp = {
    services.xrdp = {
      enable = true;
      openFirewall = true;
      audio.enable = true;
      defaultWindowManager = "startplasma-x11";
    };
  };
}

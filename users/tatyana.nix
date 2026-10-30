{
  flake.nixosModules.tatyana = {pkgs, ...}: {
    users.users.tatyana = {
      uid = 1001;
      isNormalUser = true;
      group = "tatyana";
      extraGroups = ["designers"];
      home = "/var/empty";
      createHome = false;
      shell = pkgs.shadow;
      hashedPassword = "!";
    };
    users.groups.tatyana.gid = 1001;
  };
}

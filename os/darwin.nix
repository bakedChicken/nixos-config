{
  self,
  inputs,
  lib,
  flake-parts-lib,
  ...
}: {
  options.flake = flake-parts-lib.mkSubmoduleOptions {
    darwinModules = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = {};
    };
  };

  config.flake.darwinModules.darwin = {
    imports = [
      inputs.agenix.darwinModules.default
      inputs.agenix-rekey.darwinModules.default
      self.darwinModules.common
    ];

    system.stateVersion = 6;
  };
}

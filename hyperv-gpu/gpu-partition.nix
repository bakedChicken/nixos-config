{
  flake.nixosModules.hyperv-gpu-pv =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # dxgkrnl-dkms documents kernels 6.8.0-6.17.0 as compatible with the
      # linux-msft-wsl-6.6.y patch set (see ./dxgkrnl.nix); the aarch64 host's
      # linuxPackages_latest tracks a much newer kernel that these
      # out-of-tree patches are not expected to apply/compile against.
      boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_12;

      boot.extraModulePackages = [
        (config.boot.kernelPackages.callPackage ./dxgkrnl.nix { })
        (config.boot.kernelPackages.callPackage ./vgem.nix { })
      ];
      boot.kernelModules = [
        "dxgkrnl"
        "vgem"
      ];

      services.udev.extraRules = ''
        KERNEL=="dxg", GROUP="video", MODE="0660"
      '';

      users.users.artur.extraGroups = [
        "video"
        "render"
      ];

      # nixpkgs' mesa already builds the "d3d12" gallium driver (Dozen for
      # Vulkan, d3d12/zink for OpenGL) that talks to /dev/dxg; this just
      # wires up the standard driver search paths.
      hardware.graphics.enable = true;

      # The actual GPU vendor driver (libd3d12.so, libdxcore.so, and the
      # vendor's own WSL-targeted .so files, e.g. NVIDIA's libnvidia-*.so)
      # are proprietary Windows binaries with no Nix-fetchable source: they
      # must be copied from the Windows driver store into this directory by
      # hand (see the deployment instructions). This module only prepares
      # the location and the dynamic linker config for them.
      systemd.tmpfiles.rules = [
        "d /usr/lib/wsl/lib 0755 root root -"
        "d /usr/lib/wsl/drivers 0755 root root -"
      ];
      # NixOS doesn't ship a top-level /etc/ld.so.conf that includes
      # ld.so.conf.d/*.conf, so ldconfig needs the directory passed directly.
      # NixOS-built binaries also don't reliably consult /etc/ld.so.cache for
      # dlopen()-by-soname, so back it up with LD_LIBRARY_PATH too.
      system.activationScripts.wslLdconfig = lib.stringAfter [ "etc" ] ''
        ${pkgs.glibc.bin}/bin/ldconfig -C /etc/ld.so.cache /usr/lib/wsl/lib
      '';
      environment.variables.LD_LIBRARY_PATH = [ "/usr/lib/wsl/lib" ];

      environment.systemPackages = with pkgs; [
        mesa-demos
        vulkan-tools
        libva-utils
        clinfo
      ];
    };
}

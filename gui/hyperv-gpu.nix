{
  flake.nixosModules.hyperv-gpu-pv =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      kernel = config.boot.kernelPackages.kernel;
      kernelModuleMakeFlags = config.boot.kernelPackages.kernelModuleMakeFlags;

      wsl2KernelSrc = pkgs.fetchgit {
        url = "https://github.com/microsoft/WSL2-Linux-Kernel.git";
        rev = "14794180686c2fb6307fbe359c359bec765249f3";
        sparseCheckout = [
          "drivers/hv/dxgkrnl"
          "drivers/gpu/drm/vgem"
          "include"
        ];
        hash = "sha256-+nvNsjXconUeu3KwOJqglqXClBcxp2ymBPmNYdBb+ik=";
      };

      buildOutOfTreeModule =
        {
          name,
          subdir,
          configVar,
          patches ? [ ],
          extraMakefile ? "",
        }:
        pkgs.stdenv.mkDerivation {
          pname = name;
          version = "6.18-${lib.substring 0 7 wsl2KernelSrc.rev}";
          src = wsl2KernelSrc;
          inherit patches;

          postPatch = ''
            sed -i 's/$(${configVar})/m/' ${subdir}/Makefile
          '' + lib.optionalString (extraMakefile != "") ''
            cat >> ${subdir}/Makefile <<"MAKEFILE_EOF"
            ${extraMakefile}
            MAKEFILE_EOF
          '';

          hardeningDisable = [ "pic" ];
          nativeBuildInputs = kernel.moduleBuildDependencies;
          makeFlags = kernelModuleMakeFlags;

          buildPhase = ''
            runHook preBuild
            make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
              M=$PWD/${subdir} \
              modules
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            install -D ${subdir}/${name}.ko \
              $out/lib/modules/${kernel.modDirVersion}/kernel/${subdir}/${name}.ko
            runHook postInstall
          '';

          meta = {
            license = lib.licenses.gpl2Only;
            platforms = [ "x86_64-linux" ];
          };
        };

      dxgkrnl = buildOutOfTreeModule {
        name = "dxgkrnl";
        subdir = "drivers/hv/dxgkrnl";
        configVar = "CONFIG_DXGKRNL";
        patches = [
          (pkgs.fetchpatch {
            name = "0001-Add-a-gpu-pv-support.patch";
            url = "https://content.staralt.dev/dxgkrnl-dkms/main/linux-msft-wsl-5.15.y/0001-Add-a-gpu-pv-support.patch";
            hash = "sha256-gsypOrRPrut6jWdH++ed2++E3M2uGfNt+oZrGtDgYm4=";
          })
        ];
        extraMakefile = ''
          ccflags-y += -I$(PWD)/include -D_MAIN_KERNEL_ -I${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include/linux -include ${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include/linux/vmalloc.h
        '';
      };

      vgem = buildOutOfTreeModule {
        name = "vgem";
        subdir = "drivers/gpu/drm/vgem";
        configVar = "CONFIG_DRM_VGEM";
      };
    in
    {
      boot.extraModulePackages = [
        dxgkrnl
        vgem
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

      hardware.graphics.enable = true;

      systemd.tmpfiles.rules = [
        "d /usr/lib/wsl/lib 0755 root root -"
        "d /usr/lib/wsl/drivers 0755 root root -"
      ];

      environment.variables.LD_LIBRARY_PATH = [ "/usr/lib/wsl/lib" ];

      systemd.user.settings.Manager.DefaultEnvironment = "LD_LIBRARY_PATH=/usr/lib/wsl/lib";

      environment.systemPackages = with pkgs; [
        mesa-demos
        vulkan-tools
        libva-utils
        clinfo
      ];
    };
}

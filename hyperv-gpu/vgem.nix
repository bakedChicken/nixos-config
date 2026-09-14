# vgem ("virtual GEM"): a dummy DRM driver that hands out real GEM buffer
# objects backed by plain memory, without any real display hardware.
#
# Mesa's "d3d12" gallium driver (used by dxgkrnl/Dozen, see ./dxgkrnl.nix)
# does not implement GBM, so wlroots-based Wayland compositors (Sway) can't
# allocate buffers directly against /dev/dxg and silently fall back to
# llvmpipe software rendering. vgem provides the GBM-compatible DRM device
# those compositors need; buffers allocated on it are then shared with the
# real d3d12/Dozen renderer over dma-buf, the same trick WSLg's Weston uses.
# This is dxgkrnl-dkms install.sh's "-g/--install-vgem" option, packaged the
# same way as dxgkrnl itself.
{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
  fetchgit,
  fetchpatch,
}:

stdenv.mkDerivation {
  pname = "vgem";
  version = "6.6-a07f9ea";

  src = fetchgit {
    url = "https://github.com/microsoft/WSL2-Linux-Kernel.git";
    rev = "a07f9ea8a99139913acbcc1c160b132cb2a49c81"; # tip of linux-msft-wsl-6.6.y as of 2026-09-14
    sparseCheckout = [ "drivers/gpu/drm/vgem" ];
    hash = "sha256-aRy0gLIQhCgH7WepPdMrbCSsbiBOnVybn8/u8V5d6GI=";
  };

  patches = [
    (fetchpatch {
      name = "0001-Do-not-set-the-deprecated-drm_driver-param.patch";
      url = "https://content.staralt.dev/dxgkrnl-dkms/main/linux-msft-wsl-6.6.y/vgem/0001-Do-not-set-the-deprecated-drm_driver-param.patch";
      hash = "sha256-2MH2ANaM4cAIdA6a1Kx/rzSJqLebQ1gm0GauxISoQRY=";
    })
    (fetchpatch {
      name = "0002-Fix-timer-related-error.patch";
      url = "https://content.staralt.dev/dxgkrnl-dkms/main/linux-msft-wsl-6.6.y/vgem/0002-Fix-timer-related-error.patch";
      hash = "sha256-dxwBknguUFK0pR4puQoq27RuwbkfXuZFPkaC9ZUtKQw=";
    })
  ];

  # Same trick as dxgkrnl.nix: the driver's Makefile only builds as
  # `obj-$(CONFIG_DRM_VGEM)`, which is unset out-of-tree.
  postPatch = ''
    sed -i 's/$(CONFIG_DRM_VGEM)/m/' drivers/gpu/drm/vgem/Makefile
  '';

  hardeningDisable = [ "pic" ];

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = kernelModuleMakeFlags;

  buildPhase = ''
    runHook preBuild
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M=$PWD/drivers/gpu/drm/vgem \
      modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -D drivers/gpu/drm/vgem/vgem.ko \
      $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/gpu/drm/vgem/vgem.ko
    runHook postInstall
  '';

  meta = {
    description = "Virtual GEM DRM driver, backported from the WSL2 kernel to give GBM-based compositors a buffer-allocation device alongside dxgkrnl";
    homepage = "https://github.com/staralt/dxgkrnl-dkms";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}

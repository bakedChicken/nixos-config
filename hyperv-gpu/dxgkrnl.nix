# dxgkrnl: the Hyper-V "DirectX Graphics Kernel" paravirtualization driver.
#
# This driver ships only in Microsoft's WSL2 kernel fork, never in mainline
# Linux, because it exists solely to let a Linux guest talk to the GPU-PV
# channel that Hyper-V exposes to WSL2 distros. Building it out-of-tree for a
# normal Hyper-V VM (as opposed to an actual WSL2 distro) is exactly what
# https://github.com/staralt/dxgkrnl-dkms automates for DKMS-based distros;
# this derivation reproduces the same source + patch set for Nix instead.
#
# Source: the linux-msft-wsl-6.6.y branch of microsoft/WSL2-Linux-Kernel,
# which staralt/dxgkrnl-dkms documents as compatible with kernels 6.8-6.17
# (see boot.kernelPackages override in ./default.nix, pinned to 6.12).
{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
  fetchgit,
  fetchpatch,
}:

stdenv.mkDerivation {
  pname = "dxgkrnl";
  version = "6.6-a07f9ea";

  src = fetchgit {
    url = "https://github.com/microsoft/WSL2-Linux-Kernel.git";
    rev = "a07f9ea8a99139913acbcc1c160b132cb2a49c81"; # tip of linux-msft-wsl-6.6.y as of 2026-09-14
    sparseCheckout = [
      "drivers/hv/dxgkrnl"
      "include"
    ];
    hash = "sha256-BGPGojhp7RjYKQdundHin24PVapbemOaMSXj1UoN4aw=";
  };

  # Order matches staralt/dxgkrnl-dkms install.sh's PATCHES list for the
  # linux-msft-wsl-6.6.y branch (non-TrueNAS case).
  patches = [
    (fetchpatch {
      name = "0001-Add-a-gpu-pv-support.patch";
      url = "https://content.staralt.dev/dxgkrnl-dkms/main/linux-msft-wsl-5.15.y/0001-Add-a-gpu-pv-support.patch";
      hash = "sha256-gsypOrRPrut6jWdH++ed2++E3M2uGfNt+oZrGtDgYm4=";
    })
    (fetchpatch {
      name = "0003-Update-get_task_comm-function.patch";
      url = "https://content.staralt.dev/dxgkrnl-dkms/main/linux-msft-wsl-6.6.y/0003-Update-get_task_comm-function.patch";
      hash = "sha256-lIDuAkp0zrL9hbvg22F+iUSrcWzMnI36tnLzVmvV0IU=";
    })
    (fetchpatch {
      name = "0004-Fix-timer-related-error.patch";
      url = "https://content.staralt.dev/dxgkrnl-dkms/main/linux-msft-wsl-6.6.y/0004-Fix-timer-related-error.patch";
      hash = "sha256-3LJZcdSOzr8BenpwxI5/h4EsBTCkHDznIe4Nq/HsPkk=";
    })
    (fetchpatch {
      name = "0005-Fix-pointer-casting-error-in-dxgsyncfile.c.patch";
      url = "https://content.staralt.dev/dxgkrnl-dkms/main/linux-msft-wsl-6.6.y/0005-Fix-pointer-casting-error-in-dxgsyncfile.c.patch";
      hash = "sha256-zjE2c1V6HPeMfb9tcVzH/oPOMM5SsN3tIDS+71QTG4M=";
    })
    (fetchpatch {
      name = "0006-mmap_write_lock-before-remap_pfn_range.patch";
      url = "https://content.staralt.dev/dxgkrnl-dkms/main/linux-msft-wsl-6.6.y/0006-mmap_write_lock-before-remap_pfn_range.patch";
      hash = "sha256-T6osnrGnoMjxh1O/ic1w1dRe34/+KDqjs4dGmqV6/d0=";
    })
    (fetchpatch {
      name = "0002-Fix-eventfd_signal.patch";
      url = "https://content.staralt.dev/dxgkrnl-dkms/main/linux-msft-wsl-6.6.y/0002-Fix-eventfd_signal.patch";
      hash = "sha256-OfKlZSu1gWiHZPJ60Kt7QpNMZmp0HN3UDEOKmnpjBQ8=";
    })
  ];

  # The driver's own Makefile only builds as `obj-$(CONFIG_DXGKRNL)`, which
  # is unset when building out-of-tree; force it to build as a module.
  postPatch = ''
    sed -i 's/$(CONFIG_DXGKRNL)/m/' drivers/hv/dxgkrnl/Makefile
  '';

  hardeningDisable = [ "pic" ];

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = kernelModuleMakeFlags;

  buildPhase = ''
    runHook preBuild
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M=$PWD/drivers/hv/dxgkrnl \
      EXTRA_CFLAGS="-I$PWD/include -D_MAIN_KERNEL_ -I${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include/linux -include ${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include/linux/vmalloc.h" \
      modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -D drivers/hv/dxgkrnl/dxgkrnl.ko \
      $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/hv/dxgkrnl.ko
    runHook postInstall
  '';

  meta = {
    description = "Hyper-V GPU-PV (dxgkrnl) kernel module backported from the WSL2 kernel for use in a regular Hyper-V Linux guest";
    homepage = "https://github.com/staralt/dxgkrnl-dkms";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}

{
  flake.nixosModules.sunshine =
    { pkgs, ... }:
    {
      services.sunshine.enable = true;
      services.sunshine.autoStart = true;
      services.sunshine.capSysAdmin = true;
      services.sunshine.openFirewall = true;
      # Sunshine defaults to auto-detecting a capture backend and persisting
      # whatever it picks in ~/.config/sunshine/sunshine.conf; on this VM it
      # had latched onto "kwin" (KDE's own remote-desktop interface) from an
      # earlier KDE session, which doesn't exist under Sway.
      #
      # "wlr" (Sunshine's own hand-rolled wlr-screencopy/wlr-export-dmabuf
      # backend) was tried first and does capture, but only ever produces
      # one real frame then goes black: Sway's compositor renders in
      # software (see gui/hyperv-gpu.nix for why), so it never advertises
      # linux-dmabuf-v1 to clients, and Sunshine's own source
      # (src/platform/linux/wayland.cpp, dmabuf_t::buffer_done) has no SHM
      # fallback implemented at all - literally a `// SHM fallback would go
      # here` stub that just tears the capture down. "portal" instead goes
      # through xdg-desktop-portal-wlr's PipeWire ScreenCast (already
      # enabled via xdg.portal.wlr in gui/sway.nix), whose Sunshine-side
      # implementation (src/platform/linux/pipewire.cpp) has a real
      # software/MemPtr path alongside its DMA-BUF one, not just a stub.
      services.sunshine.settings.capture = "portal";

      # capSysAdmin runs Sunshine through a cap_sys_admin file-capability
      # wrapper (/run/wrappers/bin/sunshine). glibc's dynamic loader treats
      # any capability-bearing executable as privileged and unconditionally
      # strips LD_LIBRARY_PATH from its environment before startup (a
      # standard hardening measure), which is why NVENC's "cannot load
      # libcuda.so.1" persisted even with LD_LIBRARY_PATH correctly set at
      # the systemd-user-manager level (confirmed by checking
      # /proc/<pid>/environ on the running wrapped process). RPATH baked
      # into the binary itself isn't environment-derived, so it survives
      # that stripping; force old-style DT_RPATH (not DT_RUNPATH) so it
      # also applies to libcuda.so.1 being dlopen()'d at runtime, not just
      # sunshine's own directly-linked libraries.
      services.sunshine.package = pkgs.sunshine.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.patchelf ];
        # nixpkgs' sunshine package also pulls in autoPatchelfHook, which
        # recomputes RPATH from scratch during fixupPhase and was observed
        # to wipe out an addition made via postFixup entirely (confirmed by
        # inspecting the built binary's RPATH afterwards - our path was
        # simply gone). preInstallCheck runs after fixupPhase has fully
        # finished, so nothing downstream can undo it.
        preInstallCheck = (old.preInstallCheck or "") + ''
          patchelf --force-rpath --add-rpath /usr/lib/wsl/lib $out/bin/sunshine
        '';
      });

      hardware.uinput.enable = true;

      users.users.artur.extraGroups = [ "uinput" ];
    };
}

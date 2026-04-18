{ pkgs, ... }:

{
  fileSystems."/run/virtiofs-config" = {
    device = "shared-dir-config";
    fsType = "virtiofs";
    options = [
      "ro"
      "nofail"
    ];
  };

  systemd.services.mount-shared-directories = {
    description = "Mount host directories shared through VirtioFS";
    wantedBy = [ "multi-user.target" ];
    after = [ "run-virtiofs\x2dconfig.mount" ];
    requires = [ "run-virtiofs\x2dconfig.mount" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      manifest=/run/virtiofs-config/shared-directories.tsv
      if [ ! -f "$manifest" ]; then
        exit 0
      fi

      while IFS=$'\t' read -r tag mount_point read_only; do
        if [ -z "$tag" ] || [ -z "$mount_point" ]; then
          continue
        fi

        mkdir -p "$mount_point"

        if ${pkgs.util-linux}/bin/mountpoint -q "$mount_point"; then
          continue
        fi

        if [ "$read_only" = "true" ]; then
          ${pkgs.util-linux}/bin/mount -t virtiofs -o ro "$tag" "$mount_point"
        else
          ${pkgs.util-linux}/bin/mount -t virtiofs "$tag" "$mount_point"
        fi
      done < "$manifest"
    '';
  };
}

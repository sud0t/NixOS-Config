# Placeholder. install.sh replaces this file with the output of
#   nixos-generate-config --root /mnt --show-hardware-config
# for the partitions it creates on the disk named in disks.nix. It is not kept in the repository because the
# partition UUIDs change on every install; a stale copy would mount the wrong disk.
throw ''
  host/hardware-configuration.nix has not been generated for this machine.
  Install with install.sh from the live ISO, or on an installed system run:
    sudo nixos-generate-config --show-hardware-config > ~/nixos-config/host/hardware-configuration.nix
''

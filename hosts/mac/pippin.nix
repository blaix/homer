{ pkgs, ... }:
{
  imports = [ ./common.nix ];

  networking = {
    computerName = "pippin";
    hostName = "pippin";
  };

  # using a windows keyboard on pippin
  system.keyboard.swapLeftCommandAndLeftAlt = true;

  # Restart after power failure so NixOS comes back up on the dual-boot
  power.restartAfterPowerFailure = true;

  # Shire pushes a restic backup of /mnt/storage here at 03:00 (see
  # hosts/nixos/shire.nix), which needs pippin awake. Display sleep is left at
  # its default, and harddisk sleep is deliberately untouched so the external
  # backup drive can spin down between runs instead of spinning 24/7.
  power.sleep.computer = "never";

  # Spotlight is kept off /Volumes/backup so it does not churn over restic's
  # pack files. That is deliberately NOT automated here: a launchd daemon cannot
  # touch the volume at all, because removable volumes are TCC-protected and Full
  # Disk Access is granted per-executable - a daemon would need it granted to
  # /bin/sh (far too broad) or to a nix store path that changes every rebuild.
  #
  # It does not need automating either. The durable switch is a
  # .metadata_never_index file at the volume root: Spotlight honours it at mount
  # time, and because it lives ON the drive it survives replugging and follows the
  # drive to any other Mac. Created once by hand; see the pippin section of the
  # README for that and the mdutil commands.

  # match the GID that Nix was installed with on this machine
  ids.gids.nixbld = 350;
}


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

  # Spotlight indexing churns continuously over restic's pack files on the
  # backup drive. There is no nix-darwin option for mdutil, but StartOnMount
  # fires the job on every filesystem mount - so unlike a one-shot activation
  # script this re-applies whenever the drive is unplugged and reconnected,
  # not just on darwin-rebuild. RunAtLoad covers boot.
  launchd.daemons.spotlight-off-backup = {
    script = ''
      if /sbin/mount | grep -q ' on /Volumes/backup '; then
        /usr/bin/mdutil -i off /Volumes/backup
      fi
    '';
    serviceConfig = {
      RunAtLoad = true;
      StartOnMount = true;
    };
  };

  # match the GID that Nix was installed with on this machine
  ids.gids.nixbld = 350;
}


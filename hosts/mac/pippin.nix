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
  #
  # Belt and braces, because `mdutil -i off` from a launchd daemon did NOT take
  # effect on first deploy (it works fine from an interactive sudo shell, which
  # points at TCC: Full Disk Access is granted per-executable, and a bare daemon
  # does not inherit Terminal's):
  #
  #   - .metadata_never_index is a plain file at the volume root that Spotlight
  #     honours at MOUNT time. It needs no entitlement, so TCC cannot block it,
  #     and it travels with the drive to any other Mac. It only takes effect on
  #     the next mount - which is exactly the case this daemon exists for.
  #   - mdutil is still attempted, since it applies immediately when it works.
  #     It is explicitly allowed to fail without failing the job.
  #
  # Both are logged, so the next failure is not silent like the first one was.
  launchd.daemons.spotlight-off-backup = {
    script = ''
      if /sbin/mount | grep -q ' on /Volumes/backup '; then
        echo "$(date): /Volumes/backup mounted, disabling spotlight"
        touch /Volumes/backup/.metadata_never_index \
          && echo "  .metadata_never_index ok" \
          || echo "  .metadata_never_index FAILED"
        /usr/bin/mdutil -i off /Volumes/backup \
          || echo "  mdutil FAILED (expected if TCC is blocking it)"
      else
        echo "$(date): /Volumes/backup not mounted, nothing to do"
      fi
    '';
    serviceConfig = {
      RunAtLoad = true;
      StartOnMount = true;
      StandardOutPath = "/var/log/spotlight-off-backup.log";
      StandardErrorPath = "/var/log/spotlight-off-backup.log";
    };
  };

  # match the GID that Nix was installed with on this machine
  ids.gids.nixbld = 350;
}


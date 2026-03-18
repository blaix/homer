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

  # match the GID that Nix was installed with on this machine
  ids.gids.nixbld = 350;
}


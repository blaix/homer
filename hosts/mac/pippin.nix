{ pkgs, ... }:
{
  imports = [ ./common.nix ];
  
  networking = {
    computerName = "pippin";
    hostName = "pippin";
  };

  # using a windows keyboard on pippin
  system.keyboard.swapLeftCommandAndLeftAlt = true;
}


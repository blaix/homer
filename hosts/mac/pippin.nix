{ pkgs, ... }:
{
  imports = [ ./common.nix ];
  
  networking = {
    computerName = "pippin";
    hostName = "pippin";
  };
}


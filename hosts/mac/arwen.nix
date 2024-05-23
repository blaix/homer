{ pkgs, ... }:
{
  imports = [ ./common.nix ];
  
  networking = {
    computerName = "arwen";
    hostName = "arwen";
  };
}

{ pkgs, ... }:
{
  imports = [ ./common.nix ];
  
  networking = {
    computerName = "bilbo";
    hostName = "bilbo";
  };
}

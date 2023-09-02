{ config, pkgs, ... }:
{
  imports = [
    ../darwin-configuration.nix
  ];

  networking = {
    computerName = "bilbo";
    hostName = "bilbo";
  };

}

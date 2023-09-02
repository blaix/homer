{ config, pkgs, ... }:
{
  imports = [
    ../darwin-configuration.nix
  ];

  networking = {
    computerName = "arwen";
    hostName = "arwen";
  };

}

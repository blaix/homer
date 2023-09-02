{ config, pkgs, ... }:
{
  imports = [
    ../darwin-configuration.nix
  ];

  networking = {
    computerName = "gimli";
    hostName = "gimli";
  };

}

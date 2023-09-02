{ config, pkgs, ... }:
{
  imports = [
    ../darwin-configuration.nix
  ];

  networking = {
    computerName = "pippin";
    hostName = "pippin";
  };

}

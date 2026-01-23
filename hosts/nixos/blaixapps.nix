{ config, pkgs, lib, inputs, ... }:
{
  imports = [
    ./blaixapps-base.nix
    ./common.nix
    inputs.doitanyway.nixosModules.doitanyway
  ];

  # Hostname
  networking.hostName = "blaixapps";

  # Enable doitanyway service
  services.doitanyway = {
    enable = true;
    domain = "dia.blaix.com";
    acmeEmail = "justin@blaix.com";
    enableBackups = true;
  };
}

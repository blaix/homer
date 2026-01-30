{ config, pkgs, lib, inputs, ... }:
{
  imports = [
    ./blaixapps-base.nix
    ./common.nix
    inputs.doitanyway.nixosModules.doitanyway
    inputs.growth.nixosModules.growth
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

  # Enable growth service
  services.growth = {
    enable = true;
    domain = "growth.blaix.com";
    acmeEmail = "justin@blaix.com";
    appPort = 3030;
    ws4sqlPort = 12322;
    basicAuth.enable = true;
  };
}

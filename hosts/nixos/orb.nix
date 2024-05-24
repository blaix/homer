{ config, pkgs, lib, ... }:
{
  imports = [ 
    /etc/nixos/configuration.nix
    ./common.nix
  ];

  users.groups.justin = {};
  users.users.justin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    group = "justin";
  };
}

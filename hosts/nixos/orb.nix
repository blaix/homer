{ config, pkgs, lib, ... }:
{
  imports = [ 
    # Machine-specific config set up by orb.
    /etc/nixos/configuration.nix
    
    # My own common nixos configs.
    ./common.nix
  ];

  users.groups.justin = {};
  users.users.justin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    group = "justin";
  };
}

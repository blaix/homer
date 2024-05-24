{ pkgs, ... }:
{
  imports = [ ../common.nix ];
  
  # ---------------------------------------------------------------------------
  #   Settings shared among all my NixOs systems
  # ---------------------------------------------------------------------------
  
  # create a group to match the default on mac
  users.groups.staff = {};

}

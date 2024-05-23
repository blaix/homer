{ pkgs, ... }:
{
  imports = [ ../common.nix ];
  
  # ---------------------------------------------------------------------------
  #   Settings shared among all my NixOs systems
  # ---------------------------------------------------------------------------

  users.users.justin.home = "/home/justin";
  
  # Leave this alone. 
  # It's set when you first install nix-darwin.
  # Only change via a full system reinstall.
  system.stateVersion = 4;
}

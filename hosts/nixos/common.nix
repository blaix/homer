{ pkgs, ... }:
{
  # ---------------------------------------------------------------------------
  #   Settings shared among all my NixOs systems
  # ---------------------------------------------------------------------------
  
  imports = [ ../common.nix ];
  
  users.defaultUserShell = pkgs.zsh;
}

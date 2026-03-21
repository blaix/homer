{ pkgs, ... }:
{
  # ---------------------------------------------------------------------------
  #   Settings shared among all my NixOs systems
  # ---------------------------------------------------------------------------
  
  imports = [ ../common.nix ];
  
  users.defaultUserShell = pkgs.zsh;

  # Enable mosh, opens UDP ports 60000 ... 61000
  programs.mosh.enable = true;
}

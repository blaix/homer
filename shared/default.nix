{ pkgs ? import <nixpkgs> {}, ... }:
let
  taskfiles = import (builtins.fetchGit {
    url = "https://codeberg.org/blaix/taskfiles.git";
    rev = "daca863f2b2e833c4f8f8e8eb4e0d42dcd3163f3";
  });
in
{
  # https://nixos.wiki/wiki/Nix_command 
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # System-level packages to install. Try to keep these to cli packages only
  # and use machine-specific modules for dessktop applications.
  # To search available packages by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = with pkgs; [
    bat
    diff-so-fancy
    direnv
    fd
    fzf
    gcc
    git
    gnumake
    htop
    man
    neofetch # print sys info + ascii logo in cli
    neovim
    ripgrep # needed for some nvim plugins
    shellcheck
    tmux
    tree
    unzip
    vim
    (callPackage taskfiles {})
  ];

  fonts = {
    fontDir.enable = true;
    fonts = [
      pkgs.meslo-lgs-nf
      # pkgs.nerdfonts
    ];
  };
  
}

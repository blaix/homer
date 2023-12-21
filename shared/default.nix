{ pkgs ? import <nixpkgs> {}, ... }:
let
  taskfiles = import (builtins.fetchGit {
    url = "https://codeberg.org/blaix/taskfiles.git";
    rev = "d50d177cc57e9e8701512733c4c31933afe774f6";
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
    devbox
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

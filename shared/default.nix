{ pkgs ? import <nixpkgs> {}, ... }:
let
  tasker = import (builtins.fetchGit {
    url = "https://codeberg.org/blaix/tasker.git";
    rev = "99537a01b52319e75acda47a7e73afa33f47642d";
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
    man
    neofetch # print sys info + ascii logo in cli
    neovim
    ripgrep # needed for some nvim plugins
    tmux
    tree
    unzip
    vim
    (callPackage tasker {})
  ];

  fonts = {
    fontDir.enable = true;
    fonts = [
      pkgs.meslo-lgs-nf
      # pkgs.nerdfonts
    ];
  };
  
}

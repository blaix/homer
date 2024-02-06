{ pkgs ? import <nixpkgs> {}, ... }:
let
  taskfiles = import (builtins.fetchGit {
    url = "https://codeberg.org/blaix/taskfiles.git";
    rev = "a57983a85a2adc1bbd3f342ec47380454e008140";
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
    bat # better cat
    catimg # cat for images
    diff-so-fancy
    direnv
    fd
    flyctl
    fzf
    gcc
    git
    glow # render pretty markdown on the cli
    gnumake
    htop
    man
    nb
    neofetch # print sys info + ascii logo in cli
    neovim
    nmap
    nodePackages.degit
    pandoc
    ripgrep
    shellcheck
    termpdfpy # cli vim-like ebook reader 
    tig # ncurses git repository browser
    tmux
    tree
    unzip
    vim
    visidata # view tabular data on the command line
    viu # terminal image viewer (beautiful!)
    w3m # text-based web browser
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

{ pkgs ? import <nixpkgs> {}, ... }:
let
  taskfiles = import (builtins.fetchGit {
    url = "https://codeberg.org/blaix/taskfiles.git";
    rev = "8de7d5f7f1d863e4a444ef1304c242831b5be7e1";
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
    wget
    (callPackage taskfiles {})

    # needed for LazyVim
    lazygit
    tree-sitter
    python311Packages.pynvim
    vimPlugins.nvim-treesitter.withAllGrammars # needed for LazyVim
  ];

  fonts = {
    fontDir.enable = true;
    fonts = [
      pkgs.meslo-lgs-nf
      # pkgs.nerdfonts
    ];
  };
  
}

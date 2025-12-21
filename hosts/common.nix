{ pkgs, lib, ... }:
let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  unsupported = builtins.abort "Unsupported platform";
  taskfiles = import (builtins.fetchGit {
    url = "https://codeberg.org/blaix/taskfiles.git";
    rev = "a57983a85a2adc1bbd3f342ec47380454e008140";
  });
in
{
  # ---------------------------------------------------------------------------
  #   Base-level system settings common to all machines
  # ---------------------------------------------------------------------------

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "root" "justin" ];
  nixpkgs.config.allowUnfree = true;
  nix.package = pkgs.nix;

  programs.zsh.enable = true;

  # optimize and garbage collect automatically to keep disk usage low
  nix.optimise.automatic = true;
  nix.gc = {
    automatic = lib.mkDefault true;
    options = lib.mkDefault "--delete-older-than 7d";
  };

  # Disable auto-optimise-store because of this issue:
  #   https://github.com/NixOS/nix/issues/7273
  # "error: cannot link '/nix/store/.tmp-link-xxxxx-xxxxx' to '/nix/store/.links/xxxx': File exists"
  nix.settings = {
    auto-optimise-store = false;
  };

  # ---------------------------------------------------------------------------
  #    Packages common to all machines
  # ---------------------------------------------------------------------------

  # Try to keep these to common cli-only packages.
  # OS-specific or desktop apps should go in hosts/[mac|nixos]/common.nix

  environment.systemPackages = with pkgs; [
    bat # better cat
    catimg # cat for images
    claude-code
    comma # run binaries that aren't installed
    devbox
    devenv
    diff-so-fancy
    direnv
    entr
    fd
    fzf
    gcc
    gh
    git
    gnumake
    gnupg
    gren
    htop
    just
    man
    neofetch # print sys info + ascii logo in cli
    neovim
    nmap
    nodejs_22
    # failing to build on unstable
    #nodePackages.degit
    pandoc
    python3
    python313Packages.pip
    rename
    ripgrep
    shellcheck
    tig # ncurses git repository browser
    tmux
    tree
    unzip
    visidata # view tabular data on the command line
    viu # terminal image viewer (beautiful!)
    w3m # text-based web browser
    (callPackage taskfiles {})
  ];

  fonts = {
    packages = [
      pkgs.meslo-lgs-nf
    ];
  };
}

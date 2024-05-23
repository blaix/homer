{ pkgs, lib, ... }:
{
  # ---------------------------------------------------------------------------
  #   Base-level system settings common to all machines
  # ---------------------------------------------------------------------------

  users.users.justin.name = "justin";
  # home set in hosts/[mac|nixos]/common.nix

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;
  nix.package = pkgs.nix;

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;

  # do garbage collection weekly to keep disk usage low
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
    visidata # view tabular data on the command line
    viu # terminal image viewer (beautiful!)
    w3m # text-based web browser
  ];

  fonts = {
    fontDir.enable = true;
    fonts = [
      pkgs.meslo-lgs-nf
    ];
  };
}

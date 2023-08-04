{ config, pkgs, ... }:

let 
  home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/release-23.05.tar.gz"; 
in
{
  imports = [
    (import "${home-manager}/nix-darwin")
    ../shared.nix
  ];

  users.users.justin = {
    name = "justin";
    home = "/Users/justin";
  };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      # remove all homebrew-installed things not listed here 
      cleanup = "zap";
    };
    # Find casks at https://formulae.brew.sh/cask/
    casks = [
      # "1password"
      # "amethyst"
      # "firefox"
      "iterm2"
      # "slack"
      # "thunderbird"
    ];
  };
  
  # Use a custom configuration.nix location.
  # $ darwin-rebuild switch -I darwin-config=$HOME/.config/nixpkgs/darwin/configuration.nix
  # environment.darwinConfig = "$HOME/.config/nixpkgs/darwin/configuration.nix";

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;
  # nix.package = pkgs.nix;

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true;  # default shell on catalina
  # programs.fish.enable = true;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;

  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
  };
}

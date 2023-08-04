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
      "1password"
      "amethyst"
      "firefox"
      "iterm2"
      "obsidian"
      "slack"
      "thunderbird"
    ];
  };

  # TODO: this should be on machine-specific configs
  networking = {
    computerName = "arwen";
    hostName = "arwen";
  };

  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
  };

  # For available options / examples, see:
  # https://github.com/LnL7/nix-darwin/blob/master/tests/system-defaults-write.nix
  system.defaults = {
    dock = {
      autohide = true;
      mru-spaces = false; # don't auto-rearrange spaces
    };
    spaces = {
      spans-displays = true; # all displays in one space
    };
    NSGlobalDomain = {
      AppleKeyboardUIMode = 3; # full keyboard access
      InitialKeyRepeat = 10;
      KeyRepeat = 2;
    };
    CustomUserPreferences = {
      "com.apple.controlcenter" = {
        Bluetooth = 18; # show in menu bar
      };
    };
  };

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;
  # nix.package = pkgs.nix;

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true;  # default shell on catalina
  # programs.fish.enable = true;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;

  # avoid need for a logout/login cycle for new settings to take effect
  system.activationScripts.postUserActivation.text = ''
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';
}

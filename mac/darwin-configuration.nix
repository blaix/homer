{ config, pkgs, lib, ... }:

let 
  home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/release-23.05.tar.gz"; 
in
{
  imports = [
    (import "${home-manager}/nix-darwin")
    ../shared/default.nix
  ];

  users.users.justin = {
    name = "justin";
    home = "/Users/justin";
  };

  home-manager.users.justin = (
    # mac-specific home config here  
    (import ../shared/home.nix { pkgs = pkgs; lib = lib; }) // {
      # programs.ssh = {
      #   enable = true;
      #   extraConfig = ''
      #     Host *
      #     	IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
      #   '';
      # };
    }
  );

  # -----------------------------------------------------------------------------
  # See https://daiderd.com/nix-darwin/manual/index.html for available options.
  # -----------------------------------------------------------------------------

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      # remove all homebrew-installed things not listed here 
      cleanup = "zap";
    };
    # mac-specific cli-based packages.
    # prefer nix pkgs in shared.nix whenever possible.
    brews = [
      "git-gui" # mac git no longer comes with gitk!
      "xcodegen"
    ];
    # Find casks at https://formulae.brew.sh/cask/
    casks = [
      "1password"
      "amethyst"
      "cyberduck"
      "drawio"
      "dropbox"
      "firefox"
      "google-chrome"
      "kitty"
      "michaelvillar-timer"
      "obsidian"
      "orbstack"
      "postman"
      "slack"
      "steam"
      "spotify"
      "thunderbird"
      "visual-studio-code"
    ];
  };

  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
  };

  # For available options / examples, see:
  # https://github.com/LnL7/nix-darwin/blob/master/tests/system-defaults-write.nix
  # and the bottom of:
  # https://medium.com/@zmre/nix-darwin-quick-tip-activate-your-preferences-f69942a93236
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
      InitialKeyRepeat = 12;
      KeyRepeat = 2;
      NSAutomaticSpellingCorrectionEnabled = false;
    };
    CustomUserPreferences = {
      "com.apple.controlcenter" = {
        Bluetooth = 18; # show in menu bar
      };
      "com.microsoft.VSCode" = {
        # Enable key-repeat on hold in vim mode
        # https://vimforvscode.com/enable-key-repeat-vim
        ApplePressAndHoldEnabled = false;
      };
    };
  };
  
  # WIP
  #
  ## Tiling window manager
  ## https://github.com/koekeishiya/yabai
  #services.yabai = { 
  #  enable = true;
  #  layout = "bsp";
  #};

  ## Keyboard shortcuts that work with yabai
  ## https://github.com/koekeishiya/skhd
  #services.skhd = {
  #  enable = true;
  #};

  ## Status bar that works well with yabai
  ## https://github.com/FelixKratz/SketchyBar
  #services.sketchybar = {
  #  enable = true;
  #};
  
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

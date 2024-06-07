{ pkgs, ... }:
{
  imports = [ ../common.nix ];
  
  # ---------------------------------------------------------------------------
  #   Settings shared among all my Macs
  # ---------------------------------------------------------------------------

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;

  users.users.justin = {
    name = "justin";
    home = "/Users/justin";
  };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap"; # remove brew packages not listed here
    };
    # Find casks at https://formulae.brew.sh/cask/
    casks = [
      "1password"
      "amethyst"
      "crystalfetch" # for downloading windows isos
      "cyberduck"
      "discord"
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
      "utm" # for running windows
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
      InitialKeyRepeat = 12; # lower = faster
      KeyRepeat = 2; # lower = fast
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
  
  # avoid need for a logout/login cycle for new settings to take effect
  # not sure if this is actually working?
  system.activationScripts.postUserActivation.text = ''
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';

  # Leave this alone. 
  # It's set when you first install nix-darwin.
  # Only change via a full system reinstall.
  system.stateVersion = 4;
}

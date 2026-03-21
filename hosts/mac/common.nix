{ pkgs, inputs, ... }:
{
  # Settings for ALL of my systems:
  imports = [ ../common.nix ];
  
  # ---------------------------------------------------------------------------
  #   Settings shared among all my Macs:
  # ---------------------------------------------------------------------------

  nixpkgs.overlays = [ inputs.komorebi.overlays.default ];

  users.users.justin = {
    name = "justin";
    home = "/Users/justin";
  };

  # Add my public ssh keys. nix-darwin doesn't have a setting like nixos does
  # for managing these, so I'm just writing the file directly.
  system.activationScripts.postActivation.text = let
    keys = import ../../users/justin/ssh-keys.nix;
    keyFile = builtins.concatStringsSep "\n" keys;
  in ''
    mkdir -p /Users/justin/.ssh
    echo '${keyFile}' > /Users/justin/.ssh/authorized_keys
    chown justin /Users/justin/.ssh/authorized_keys
    chmod 600 /Users/justin/.ssh/authorized_keys
  '';

  system.primaryUser = "justin";

  nix.settings = {
    # Increase default buffer size to prevent bottlenecks during nix builds
    # when downloads outpace decompression (I was seeing this a lot on Dia).
    download-buffer-size = 268435456; # 256 MiB
  };

  # nix packages specific to macs
  environment.systemPackages = [

    # Promising tiling window manager for mac.
    # Seems a little too early-stage for daily use.
    # If I do end up using it, some things I will need to do:
    # * be sure to grab a license for work usage: https://lgug2z.com/software/komorebi/
    # * considering sponsoring him: https://github.com/sponsors/LGUG2Z
    # * manage ~/.config/komorebi declaritively (generated via `komorebic quickstart`)
    # * enable skhd for hotkeys. See ~/.config/komorebi/skhdrc
    #pkgs.komorebi-full

  ];

  # homebrew packages
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap"; # remove brew packages not listed here
    };
    brews = [
      "git-gui" # Bring back gitk: https://www.bstefanski.com/blog/gitk-on-macos
    ];
    # Find casks at https://formulae.brew.sh/cask/
    casks = [
      "1password"
      "alfred"
      "aws-vpn-client"
      "amethyst"
      "charles" # watch network requests on mac
      "crystalfetch" # for downloading windows isos
      "cyberduck" 
      "discord"
      "drawio"
      "dropbox"
      "firefox"
      "ghostty"
      "google-chrome"
      "michaelvillar-timer"
      "netnewswire"
      "obsidian"
      "orbstack"
      "postman"
      "slack"
      "steam"
      "utm" # for running windows
      "vivaldi"
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

      # When I switch apps, *don't* switch to a space
      # with a window open for that app.
      AppleSpacesSwitchOnActivate = false;

      # Just repeat the key when I hold it down,
      # don't show a suggestions tooltip.
      ApplePressAndHoldEnabled = false;
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
  
  # Leave this alone. 
  # It's set when you first install nix-darwin.
  # Only change via a full system reinstall.
  system.stateVersion = 4;
}

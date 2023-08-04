{ pkgs, ... }:
{
  # https://nixos.wiki/wiki/Nix_command 
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  # Note: .app files that would normally be under "/Applications"
  # will be under a "/Applications/Nix Apps" symlink to the nix store.
  environment.systemPackages = with pkgs; [
    bat
    diff-so-fancy
    direnv
    gcc
    git
    gnumake
    man
    neovim
    tmux
    unzip
    vim
  ];

  fonts = {
    fontDir.enable = true;
    fonts = [
      pkgs.meslo-lgs-nf
      pkgs.nerdfonts
    ];
  };
  
  home-manager.users.justin = {
    home.stateVersion = "23.05";
  
    programs.bash = {
      enable = true;
      sessionVariables = {
        EDITOR = "nvim";
      };
      shellAliases = {
        cat = "bat";
        vim = "nvim";
  
        # git stuff
        gfo = "git fetch origin";
        gmo = "git merge --ff-only origin/main";
        s = "git st";
        b = "git b";
        d = "git d";
      };
    };
  
    programs.direnv = {
      enable = true;
      enableBashIntegration = true;
    };
  
    programs.git = {
      enable = true;
      userName = "Justin Blake";
      userEmail = "justin@blaix.com";
      aliases = {
        b = "branch";
        d = "diff";
        co = "checkout";
        st = "status -sb";
        ci = "commit -v";
      };
      extraConfig = {
        github = {
          user = "blaix";
        };
        init = {
          defaultBranch = "main";
        };
        pager = {
          branch = false;
        };
      };
    };
  
    programs.helix = {
      enable = true;
      settings = {
        theme = "dracula";
        editor = {
          auto-format = true;
          true-color = true;
          cursor-shape = {
            insert = "bar";
            normal = "block";
            select = "underline";
          };
          gutters = [
            "diagnostics"
            "line-numbers"
            "spacer"
          ];
        };
        keys = {
          normal = {
            esc = [
              "collapse_selection"
              "keep_primary_selection"
            ];
            "C-[" = [
              "collapse_selection"
              "keep_primary_selection"
            ];
          };
          insert = {
            # ctrl-[ doesn't act as escape in helix :(
            # https://github.com/helix-editor/helix/issues/6551
            "C-[" = [
              "normal_mode"
            ];
          };
        };
      };
    };
  
    programs.tmux = {
      enable = true;
      prefix = "C-a";
      extraConfig = ''
        set -g default-terminal "xterm-256color"
        # Prevent delay when hitting esc
        set -g escape-time 10
        # Switch to last window with ctrl-a, just like screen
        bind-key C-a last-window
        # Send a literal ctrl-a with c-a a
        bind a send-keys C-a
        # Set status bar
        set -g status-bg black
        set -g status-fg white
        set -g status-right '"#H" %a %b-%d %I:%M%p'
        # Lots of room for long session names
        set -g status-left-length 30
        # Big history
        set-option -g history-limit 9000
        # Use vim movements to move around panes
        bind h select-pane -L
        bind j select-pane -D
        bind k select-pane -U
        bind l select-pane -R
        # Use capital vim movements to resize panes
        bind J resize-pane -D 2
        bind K resize-pane -U 2
        bind H resize-pane -L 2
        bind L resize-pane -R 2
      '';
    };
  
    programs.zsh = {
      enable = true;
      sessionVariables = {
        EDITOR = "nvim";
      };
      shellAliases = {
        cat = "bat";
        vim = "nvim";
        # git aliases
        gfo = "git fetch origin";
        gmo = "git merge --ff-only origin/main";
        s = "git st";
        b = "git b";
        d = "git d";
      };
      oh-my-zsh = {
        enable = true;
        plugins = [
          "brew"
        ];
      };
      plugins = [
        { name = "powerlevel10k";
          src = pkgs.zsh-powerlevel10k;
          file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
        }
        { name = "powerlevel10k-config";
          # To generate a new config, run `p10k configure`
          # Then `mv ~/.p10k.zsh` to `homer/zsh/p10k/`
          src = ./zsh/p10k;
          file = "p10k.zsh";
        }
      ];
    };
  
    xdg.configFile = {
      "nvim" = {
        enable = true;
        recursive = true;
        source = builtins.fetchGit {
          url = https://github.com/NvChad/NvChad;
        };
      };
    };
  };
}

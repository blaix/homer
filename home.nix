{ config, pkgs, ... }:
{
  # ---------------------------------------------------------------------------
  #   User home and dotfile settings common to all machines
  # ---------------------------------------------------------------------------

  # Leave this alone.
  # It's set and should only ever change on a full re-install.
  home.stateVersion = "23.05";
  programs.home-manager.enable = true; 

  # Environment variables
  home.sessionVariables = {
    EDITOR = "nvim";
    TASKFILES_HOME = "$HOME/dia";

    # opt out of project telemetries
    ET_NO_TELEMETRY = 1;          # eternal terminal
    NEXT_TELEMETRY_DISABLED = 1;  # next.js

    # Unfortunately ssh doesn't recognize ghostty's terminfo. Until it does,
    # I'm opting out of ghostty's advanced features in exchange for better a
    # terminal that actually works the way I'm used to when I ssh to another
    # machine (especially another one of my own machines on my network).
    # See https://github.com/ghostty-org/ghostty/discussions/3161
    TERM = "xterm-256color";
  };

  # Extra directories to add to PATH
  home.sessionPath = [
    "$HOME/homer/shared/bin"
  ];

  # librewolf settings in nix home manager are not supported on mac.
  # so writing config file directly instead.
  # https://librewolf.net/docs/settings/#where-do-i-find-my-librewolfoverridescfg
  home.file.".librewolf/librewolf.overrides.cfg" = {
    # https://librewolf.net/docs/settings/
    text = ''
      defaultPref("identity.fxaccounts.enabled", true); 
    '';
  };

  # using the cask until the nix build is fixed
  # https://github.com/NixOS/nixpkgs/issues/368742
  #programs.ghostty = {
  #  enable = true;
  #  settings = {
  #    theme = "catppuccin-mocha";
  #    font-feature = "-calt"; # no glyphs
  #    keybind = [
  #      # make zsh understand ctrl-[ as ESC
  #      # https://github.com/ghostty-org/ghostty/issues/2976
  #      "ctrl+left_bracket=text:\x1b"
  #    ];
  #  };
  #};

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;

    # faster use_nix implementation
    # https://github.com/nix-community/nix-direnv
    nix-direnv.enable = true;
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
      ci = "commit -v -S";
      gr = "log --graph --all";
      gmo = "git merge --ff-only origin/master";
      fetch = "fetch -p";
    };
    ignores = [
      ".DS_Store"
      ".direnv"
      ".envrc"
    ];
    hooks = {
      pre-commit = ./git/hooks/pre-commit.sh;
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
      fetch = {
        prune = true;
      };
    };
  };

  programs.neovim = {
    enable = true;
    extraLuaConfig = builtins.readFile ./nvim/init.lua;
    plugins = with pkgs.vimPlugins; [
      nvim-tree-lua
      nvim-lspconfig
      nvim-treesitter.withAllGrammars
      vim-commentary
      vim-prisma
      vim-just
      telescope-nvim
      bufferline-nvim
      neogit
      vim-markdown-toc # https://github.com/mzlogin/vim-markdown-toc

      # vimwiki: I use this for GTD, projects, and notes
      # https://github.com/vimwiki/vimwiki
      vimwiki
      pkgs.vimwiki-markdown

      # themes
      catppuccin-nvim
      dracula-nvim

      # status line
      lualine-nvim
      lualine-lsp-progress

      # dependencies for other plugins:
      nvim-web-devicons
      plenary-nvim
    ];
  };

  programs.tmux = {
    enable = true;
    prefix = "C-a";
    extraConfig = ''
      set -g default-terminal "xterm-256color"
      # Use vi-style keybindings in scrollback buffer mode
      set-window-option -g mode-keys vi
      # Prevent delay when hitting esc
      set -g escape-time 10
      # Switch to last window with ctrl-a, just like screen
      bind-key C-a last-window
      # Send a literal ctrl-a with c-a a
      bind a send-keys C-a
      # Set status bar
      set -g status-bg black
      set -g status-fg white
      # Old status with date and time:
      #set -g status-right '"#H" %a %b-%d %I:%M%p'
      set -g status-right '"#H"'
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
    shellAliases = {
      flushdns = "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder";
      gr = "nix shell nixpkgs#nodejs_20 github:gren-lang/nix/0.5.2 --command gren";
      cat = "bat";
      vim = "nvim";
      fv = "nvim \"$(fzf)\"";
      t = "taskfiles";
      # navigation aliases
      pn = "cd ~/projects/prettynice";
      tf = "cd \"$TASKFILES_HOME\"";
      tfp = "cd ~/projects/taskfiles";
      homer = "cd ~/homer";
      pencils = "cd ~/projects/pencils";
      # git aliases
      gfo = "git fetch -p origin";
      gmo = "git merge --ff-only origin/main";
      s = "git st";
      b = "git b";
      d = "git d";
      # gren aliases
      initgren-054 = "devbox init && devbox add github:gren-lang/nix/0.5.4 && devbox add nodejs@22 && devbox gen direnv";
      localgren = "GREN_BIN=~/projects/gren/compiler/gren node ~/projects/gren/compiler/app";
      blaixgren = "GREN_BIN=~/projects/gren/compiler-blaix/gren node ~/projects/gren/compiler-blaix/cli.js";
      maingren = "nix shell nixpkgs#nodejs_20 github:gren-lang/nix/main --command gren";
    };
    initContent = ''
      # https://github.com/jeffreytse/zsh-vi-mode#nix
      source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
    '';
    oh-my-zsh = {
      enable = true;
      plugins = [
        "brew"
        "fzf"
      ];
    };
    plugins = [
      { name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      { name = "powerlevel10k-config";
        # To generate a new config, run `p10k configure`
        # Then `mv ~/.p10k.zsh` to `homer/zsh/p10k.zsh`
        src = ./zsh;
        file = "p10k.zsh";
      }
    ];
  };

  # degit will fail if it can't create or find this directory
  home.file.".degit/.keep" = {
    recursive = true;
    source = builtins.toFile "keep" ""; 
  };

  xdg.configFile = {
    "nvim" = {
      enable = true;
      recursive = true;
      source = ./nvim;
    };
  };
}

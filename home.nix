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
  };

  # Extra directories to add to PATH
  home.sessionPath = [
    "$HOME/homer/shared/bin"
  ];

  # Kitty terminal config
  programs.kitty = {
    enable = true;
    font = {
      name = "MesloLGS NF";
      size = 14;
    };
    themeFile = "Dracula";
    settings = {
      enable_audio_bell = "no";
    };
  };

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
    shellAliases = {
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
      # always inherit environment when using tmux
      tmux = "tmux -L default";
      # gren aliases
      initgren = "devbox init && devbox add github:gren-lang/nix/0.5.x && devbox gen direnv";
      localgren = "GREN_BIN=~/projects/gren/compiler/gren node ~/projects/gren/compiler/cli.js";
      maingren = "nix shell nixpkgs#nodejs_20 github:gren-lang/nix/main --command gren";
    };
    initExtra = ''
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
    "nvim/filetype.lua" = {
      enable = true;
      recursive = false;
      source = ./nvim/filetype.lua;
    };
  };
}

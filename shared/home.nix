{ pkgs }:
{
  home.stateVersion = "23.05";

  programs.alacritty = {
    enable = true;
  };

  programs.bash = {
    enable = true;
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
      gr = "log --graph --all";
    };
    ignores = [
      ".DS_Store"
    ];
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
    languages = {
      language = [{
        name = "css";
        auto-format = true;
        formatter = {
          command = "prettier";
          args = ["--parser" "css"];
        };
      } {
        name = "gren";
        scope = "source.gren";
        grammar = "elm";
        file-types = ["gren"];
        roots = ["gren.json"];
        auto-format = false;
      } {
        name = "html";
        auto-format = true;
        formatter = {
          command = "prettier";
          args = ["--parser" "html"];
        };
      } {
        name = "javascript";
        auto-format = true;
        formatter = {
          command = "prettier";
          args = ["--parser" "typescript"];
        };
      } {
        name = "json";
        auto-format = true;
        formatter = {
          command = "prettier";
          args = ["--parser" "json"];
        };
      } {
        name = "tsx";
        auto-format = true;
        formatter = {
          command = "prettier";
          args = ["--parser" "typescript"];
        };
      } {
        name = "typescript";
        auto-format = true;
        formatter = {
          command = "prettier";
          args = ["--parser" "typescript"];
        };
      }];
    };
    settings = {
      theme = "github_dark";
      editor = {
        auto-format = true;
        true-color = true;
        cursorline = true; # highlight current line
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

  programs.neovim = {
    enable = true;
    extraLuaConfig = builtins.readFile ./nvim/init.lua;
    plugins = with pkgs.vimPlugins; [
      nvim-tree-lua
      telescope-nvim

      # themes
      catppuccin-nvim
      dracula-nvim

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
    # nvchad is too opinionated
    # "nvim" = {
    #   enable = true;
    #   recursive = true;
    #   source = builtins.fetchGit {
    #     url = https://github.com/NvChad/NvChad;
    #   };
    # };
    "helix/runtime" = {
      enable = true;
      recursive = true;
      source = ./helix/runtime;
    };
    "nvim/filetype.lua" = {
      enable = true;
      recursive = false;
      source = ./nvim/filetype.lua;
    };
  };
}

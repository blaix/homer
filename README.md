# My personal system configuration files

My system and home settings using nix, flakes, and home manager for my macbooks and (eventually) nixos servers.

Important files:

* `flake.nix`: Entry point for all configs.
* `home.nix`: User environment settings (dotfiles, etc) via home-manager.
* `hosts/`: Machine specific settings at `[hostname].nix` and shared settings in `common.nix`.

## Usage

Test configs by building them:

```
just build [hostname]
```

or fully switch to the new config:

```
just switch [hostname]
```

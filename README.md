# Homer (aka Blaix Flakes)

My system and home settings using nix, flakes, and home manager for my macbooks and (eventually) nixos servers.

Important files:

* [`flake.nix`](/flake.nix): Entry point for all configs.
* [`home.nix`](/home.nix): User environment configs.
* [`hosts/`](/hosts): System, OS, and machine-specific configs.

## Usage: Mac

**Initial setup on new Mac:**

1. Install nix: https://nix.dev/install-nix.html

2. Clone this repo: 

  ```
  nix --extra-experimental-features nix-command --extra-experimental-features flakes run nixpkgs#git clone git@github.com:blaix/homer.git && cd homer
  ```
  
3. Choose a host name for your mac.
   Make sure it has a definitionn under `darwinConfigurations` in [`flake.nix`](/flake.nix) pointing to a `[hostname].nix` file under [`hosts/mac`](/hosts/mac).

4. Run the following, replacing `[hostname]` with the name from the previous step (e.g. `.#arwen`):

  ```
  nix --extra-experimental-features nix-command --extra-experimental-features flakes run nix-darwin -- switch --flake .#[hostname]
  ```

**After initial setup:**

* Test changes by building them: `just build [hostname]`
* Update your system to the latest changes: `just switch [hostname]`

## Usage: NixOs

**Initial setup:**

0. Log in to your nix server.
   You can create a nixos vm on mac with [orbstack](https://orbstack.dev/) (installed via configs in this repo) with:

  ```
  orb create nixos && ssh orb
  ```

1. Start a shell with `git` available:

  ```
  nix-shell -p git
  ```
  
2. Clone this repo:

  ```
  git clone git@github.com:blaix/homer.git && cd homer
  ```

3. Choose a host name.
   Make sure it has a definitionn under `nixosConfigurations` in [`flake.nix`](/flake.nix) pointing to a `[hostname].nix` file under [`hosts/nixos`](/hosts/nixos).

4. Run the following, replacing `[hostname]` with the name from the previous step (e.g. `.#orb`):
  
  ```
  sudo nixos-rebuild switch --impure --flake .#orb
  ```

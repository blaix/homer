[macos]
build HOST:
  sudo darwin-rebuild build --flake .#{{HOST}}

[macos]
switch HOST:
  sudo darwin-rebuild switch --flake .#{{HOST}}

# nixos-rebuild runs as root (so the sudo prompt comes up front, not after a
# long build), but private flake inputs on git.blaix.com need my ssh key.
git_ssh := "ssh -i " + home_directory() + "/.ssh/id_ed25519 -o UserKnownHostsFile=" + home_directory() + "/.ssh/known_hosts"

[linux]
build HOST:
  sudo env GIT_SSH_COMMAND="{{git_ssh}}" nixos-rebuild build --impure --flake .#{{HOST}}

[linux]
switch HOST:
  sudo env GIT_SSH_COMMAND="{{git_ssh}}" nixos-rebuild switch --impure --flake .#{{HOST}}

# TODO: replace dia.blaix.com with more generalized domain for blaixapps

init-blaixapps:
  nix run github:nix-community/nixos-anywhere -- --flake .#blaixapps-base --target-host root@dia.blaix.com --build-on-remote
  
# --no-reexec prevents re-exec to target's nixos-rebuild (which is x86_64-linux and can't run on this Mac)
deploy-blaixapps:
  nix run nixpkgs#nixos-rebuild -- switch --flake .#blaixapps --target-host dia.blaix.com --build-host dia.blaix.com --sudo --no-reexec

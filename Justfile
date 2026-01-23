[macos]
build HOST:
  sudo darwin-rebuild build --flake .#{{HOST}}

[macos]
switch HOST:
  sudo darwin-rebuild switch --flake .#{{HOST}}

[linux]
build HOST:
  sudo nixos-rebuild build --impure --flake .#{{HOST}}

[linux]
switch HOST:
  sudo nixos-rebuild switch --impure --flake .#{{HOST}}

# TODO: replace dia.blaix.com with more generalized domain for blaixapps

init-blaixapps:
  nix run github:nix-community/nixos-anywhere -- --flake .#blaixapps-base --target-host root@dia.blaix.com --build-on-remote
  
deploy-blaixapps:
  nix run nixpkgs#nixos-rebuild -- switch --flake .#blaixapps --target-host dia.blaix.com --build-host dia.blaix.com --use-remote-sudo


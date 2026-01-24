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

deploy-blaixapps-local FLAKE PATH:
  # copy local path to host
  rsync -av --delete {{PATH}}/ dia.blaix.com:/tmp/local-{{FLAKE}}/
  # copy homer to host
  rsync -av --delete --exclude='.direnv' --exclude='result' . dia.blaix.com:/tmp/homer-flake/
  # run the build
  ssh dia.blaix.com "sudo nixos-rebuild switch --flake /tmp/homer-flake#blaixapps --override-input {{FLAKE}} /tmp/local-{{FLAKE}}"

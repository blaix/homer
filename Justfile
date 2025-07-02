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

[macos]
build HOST:
  darwin-rebuild build --flake .#{{HOST}}

[macos]
switch HOST:
  darwin-rebuild switch --flake .#{{HOST}}

[linux]
build HOST:
  nix build .#{{HOST}}

[linux]
switch HOST:
  nix switch .#{{HOST}}

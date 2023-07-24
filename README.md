## New NixOs setup

(OrbStack: install 22.11)

```bash
orb # shell into the vm
nix --extra-experimental-features nix-command --extra-experimental-features flakes run nixpkgs#git clone git@github.com:blaix/homer.git
cd homer/nixos
./run.sh
```

## Subsequent runs

```bash
cd homer/nixos
make
```

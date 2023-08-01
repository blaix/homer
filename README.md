# System configuration files

## NixOs

Assumes a vm set up via [OrbStack](https://orbstack.dev/).

### New setup

```bash
ssh orb

# clone the repo and run setup
nix --extra-experimental-features nix-command --extra-experimental-features flakes run nixpkgs#git clone git@github.com:blaix/homer.git
cd homer/nixos
./run.sh

# reload shell environment
exit
ssh orb
```

If the git clone fails with a key error,
orbstack may not have linked them,
and you'll need to do it manually, e.g.:

```bash
ln -s /mnt/mac/Users/justin/.ssh/id_rsa /home/justin/.ssh/id_rsa
ln -s /mnt/mac/Users/justin/.ssh/id_rsa.pub /home/justin/.ssh/id_rsa.pub
```

### Existing setup

```bash
ssh orb
cd homer/nixos
make
```

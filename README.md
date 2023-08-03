# System configuration files

Focused on managing a mac with nix for now.

## Host system: nix-darwin

Base system config and packages for a mac via [nix-darwin](https://github.com/LnL7/nix-darwin).

### New setup

- [Install nix](https://github.com/NixOS/nix#installation)
- [Install nix-darwin](https://github.com/LnL7/nix-darwin#installing)

Then:

```
cd

# clone the repo and run setup
nix --extra-experimental-features nix-command --extra-experimental-features flakes run nixpkgs#git clone git@codeberg.org:blaix/homer.git
cd homer/nix-darwin
./run.sh
```

Then open a new terminal to reload the shell environment.

### Existing setup

```bash
cd ~/homer/nix-darwin
make
```

## NixOS VMs

Full NixOs running in [OrbStack](https://orbstack.dev/) VM for dev envirnments and testing.

### New setup

```bash
orb create nixos # followed by optional vm name
ssh orb # or ssh my-vm-name@orb

# clone the repo and run setup
nix --extra-experimental-features nix-command --extra-experimental-features flakes run nixpkgs#git clone git@codeberg.org:blaix/homer.git
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

## New NixOs setup

```bash
# shell into the vm
ssh orb

# if the keys aren't linked automatically by orbstack
ln -s /mnt/mac/Users/justin/.ssh/id_rsa ./
ln -s /mnt/mac/Users/justin/.ssh/id_rsa.pub ./

# checkout and run
nix --extra-experimental-features nix-command --extra-experimental-features flakes run nixpkgs#git clone git@github.com:blaix/homer.git
cd homer/nixos
./run.sh
```

## Subsequent runs

```bash
cd homer/nixos
make
```

# My personal system configuration files

Focused on managing my own mac and vms with nix for now.
Feel free to use it as an example or reference,
but it's pretty specific to me.

Most recent version is at <https://github.com/blaix/homer>.

## Mac

Base system config and packages for a mac via [nix-darwin](https://github.com/LnL7/nix-darwin).

### New setup

1.  [Install nix](https://github.com/NixOS/nix#installation)

2. [Install nix-darwin](https://github.com/LnL7/nix-darwin#installing)

3. Download and run these configs:

```
cd

# clone the repo and run setup
nix --extra-experimental-features nix-command --extra-experimental-features flakes run nixpkgs#git clone git@codeberg.org:blaix/homer.git
cd homer/mac
HOST=[host name] ./run.sh
```

4. Then close the apple terminal and open kitty terminal

Done!

### Existing setup

```bash
cd ~/homer/mac
make [host name]
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

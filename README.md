# Homer (aka Blaix Flakes)

My system and home settings using nix, flakes, and home manager for my macs, nixos vms, and servers.

Important files:

* [`flake.nix`](/flake.nix): Entry point for all configs.
* [`home.nix`](/home.nix): User environment configs.
* [`hosts/`](/hosts): System, OS, and machine-specific configs.

It's set up for myself but should be adaptable if you want to use this setup for your own systems.

## Usage

* If you haven't already, go through the [initial setup](#initial-setup)
* Test changes by building them: `just build [hostname]`
* Update your system to the latest changes: `just switch [hostname]`
* Deploy server with `just blaixapps-deploy`

## Initial setup

### Mac

1. [Install nix](https://nixos.org/download/)

2. Clone this repo: 

  ```
  nix --extra-experimental-features nix-command --extra-experimental-features flakes run nixpkgs#git clone git@github.com:blaix/homer.git && cd homer
  ```
  
3. Choose a host name for your mac.
   Make sure it has a definitionn under `darwinConfigurations` in [`flake.nix`](/flake.nix) pointing to a `[hostname].nix` file under [`hosts/mac`](/hosts/mac).

4. Install [homebrew](https://brew.sh/). (this needs to be installed as its own package, but then homebrew packages/casks/etc are managed declaratively in these configs)

5. Activate your system with the following, replacing `[hostname]` with the name from the previous step (e.g. `.#arwen`):

  ```
  sudo nix --extra-experimental-features nix-command --extra-experimental-features flakes run nix-darwin -- switch --flake .#[hostname]
  ```

6. If you are me: Import my gpg key from 1Password.

7. Going forward, you can update your system with `just switch [hostname]`.

NOTE: If some OS X settings don't seem to take affect (e.g. key repeat rate),
you may need to restart. The workarounds I've tried for this have not worked.

### NixOS (local machine or vm)

This section is for setting up a local NixOS instance you have physical access to.
For setting up a remote NixOS server, see "NixOS Remote Server" below.

#### VM on a Mac

The easiest way is with [orbstack](https://orbstack.dev/) (installed via the configs in this repo):

```
orb create nixos
```

When you're ready, you can log in to the vm with:


```
ssh orb
```

Skip to "Common NixOs Setup" Below

#### Dual-boot Apple Silicon Mac

Follow the instructions at: https://github.com/nix-community/nixos-apple-silicon/blob/main/docs/uefi-standalone.md

For the Software Preparation > Nix step, the path of least resistance is to download a release iso and copy to a usb stick with `dd` as described in the "Nix" section.

#### Other

I don't have any non-mac/non-remote nix setups so no specific instructions here.
Just use the nix docs to get a bare-bones base system set up.
Don't worry about customizing it yet.

#### Common NixOS Setup

* Choose a host name and create a config at `hosts/nixos/[hostname].nix`.
  You can base it one of the other files in that directory.
  If you're using an apple silicon mac, you should base it on `pippinix.nix`.
  Otherwise, `orb.nix` is a good bare-bones example.
  Just worry about getting the base system set up for now.
  It's easy to refine and update later.
 
* Point to your new config file under `nixosConfigurations` in [`flake.nix`](/flake.nix).

* Commit and push your new config.

* Log in to the new nix system.

* Start a shell with `git` available:

  ```
  nix-shell -p git
  ```
  
* Clone this repo:

  ```
  git clone https://github.com/blaix/homer.git && cd homer
  ```

* Run the following, replacing `[hostname]` with the host name you chose (I'm using "orb" as the hostname in these examples):
  
  ```
  sudo nixos-rebuild switch --impure --flake .#orb
  ```

This could take a very long time. Subsequent builds shouldn't take nearly as long.

* If you are me: Import my gpg key from 1Password.

### NixOS Remote Server

Right now I just have one `blaixapps` server on Hetzner.
Apps hosted on this server maintain their own flake for building the project, but are deployed from here.

1. **Provision server:**
   - Create server via Hetzner Cloud Console (preferred)
   - **Important:** Select your SSH key from the "SSH Keys" dropdown (or paste it)
     - This adds it to root's authorized_keys for initial access
     - It should be one of my keys provisioned in this repo from `users/justin/ssh-keys.nix`
   - Note the IP address

2. **Verify root access:**
   ```bash
   ssh root@<HETZNER_IP>
   ```

3. **Configure DNS:**
   - Add A record: e.g. dia.blaix.com → <HETZNER_IP>
   - Wait for propagation: `dig dia.blaix.com`

4. **Initial Installation:** `just init-blaixapps`
   - Connects as **ROOT** user to **REPLACE** the host OS with NixOs using [nixos-anywhere](https://github.com/nix-community/nixos-anywhere).
   - Uses the `hosts/nixos/base-server.nix` flake for a bare-bones, base level system.
   
6. **Verify Installation:**
   ```bash
   ssh justin@dia.blaix.com
   systemctl status  # Check system health
   ```

7. Set up server secrets (see below).

8. Deploy the full config and applications: `just deploy-blaixapps`

#### Server Secrets

These files must exist on the server and are not managed by nix:

- **`/etc/grafana-admin-password`** — Password for the Grafana `admin` user.
  ```bash
  echo 'your-secure-password' | sudo tee /etc/grafana-admin-password
  sudo chown grafana:grafana /etc/grafana-admin-password
  sudo chmod 0600 /etc/grafana-admin-password
  ```

- **`/etc/grafana-secret-key`** — Secret key used by Grafana to sign cookies and encrypt data.
  ```bash
  nix run nixpkgs#openssl -- rand -hex 32 | sudo tee /etc/grafana-secret-key
  sudo chown grafana:grafana /etc/grafana-secret-key
  sudo chmod 0600 /etc/grafana-secret-key
  ```

- **`/etc/htpasswd`** — nginx basic auth file used by several of my personal apps.
  ```bash
  nix-shell -p apacheHttpd
  sudo htpasswd -c /etc/htpasswd <username>
  ```


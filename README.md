# Homer (aka Blaix Flakes)

My system and home settings using nix, flakes, and home manager for my macs, nixos vms, and servers.

Important files:

* [`flake.nix`](/flake.nix): Entry point for all configs.
* [`home.nix`](/home.nix): User environment configs.
* [`hosts/`](/hosts): System, OS, and machine-specific configs.
* [`SECRETS.md`](/SECRETS.md): Docs for sops-nix setup.

It's set up for myself but should be adaptable if you want to use this setup for your own systems.

## Usage

* If you haven't already, go through the [initial setup](#initial-setup)
* Test changes by building them: `just build [hostname]`
* Update your system to the latest changes: `just switch [hostname]`
* Deploy server with `just blaixapps-deploy`

## Secrets and passwords

Most of this repo is declarative, but some credentials can't live in git (it's a
public repo, and the built config lands in the world-readable `/nix/store`). They're
handled two ways:

* **sops-nix** — encrypted secrets committed to the repo, decrypted per-host at
  activation using the host's SSH key. See [`SECRETS.md`](/SECRETS.md). Wired into all
  NixOS hosts; the bootstrap (personal age key from 1Password, registering a host as a
  recipient) is the one manual part.
* **Out-of-band** — a file created by hand on the machine (`chmod 600`), or an account
  created through a service's own web UI. These are **not declarative**: they must be
  redone on a from-scratch rebuild. Where a value is noted as being in **1Password**,
  that's where I keep it.

This section inventories every manual credential step, by host. It's the checklist for
standing a machine back up from nothing.

### Every NixOS host

* `passwd justin` — set the user login password (as root, on first boot). _Not needed on
  hosts that set `hashedPasswordFile` from sops (e.g. shire)._
* sops-nix bootstrap, **only if the host needs secrets**: place my personal age key
  from 1Password at `~/.config/sops/age/keys.txt`, then register the host as a recipient
  in `.sops.yaml`. Full steps in [`SECRETS.md`](/SECRETS.md).

### Every Mac

* Import my GPG key from 1Password.

### Torrent/Jellyfin Macs

* qBittorrent Web UI **admin password** (in 1Password). Plus the qBittorrent Web UI and
  Proton bind-address setup in
  [`hosts/mac/proton-portforward.nix`](/hosts/mac/proton-portforward.nix).

### shire (home media + cameras)

_Managed by sops (`secrets/shire.yaml`), **no manual step** on a rebuild — listed here
only so you know where they live:_

* **Login password** — `users.users.justin.hashedPasswordFile` (replaces `passwd justin`).
* **WireGuard server key** — `wg0-private-key`, backed up in 1Password as
  `shire wireguard wg0 private key`.
* **Frigate camera RTSP password** — `frigate-rtsp-password`, in 1Password as
  `shire frigate camera rtsp`; rendered into Frigate's environment via a sops template.
  The only related action is setting **that same password** on each camera's `admin`
  account when you provision them.

_Still manual (app accounts created through each service's own web UI / DB):_

* `sudo smbpasswd -a justin` — Samba share password.
* **Jellyfin** (`:8096`): create the admin account in the web UI; add the movie/show
  libraries.
* **Navidrome** (`:4533`): complete first-run admin setup in the web UI.
* **Komga** (`:25600`): create the admin account in the web UI; add the comics library.
* **its-mytabs** (`:47777`): create the admin account in the web UI.
* **Home Assistant** (`:8123`): complete onboarding (create admin account), then add the
  **MQTT** (`127.0.0.1:1883`) and **Frigate** (`http://127.0.0.1:5000`) integrations from
  the HA UI.
* **Frigate** (`:8971`): auth is on by default. On first successful boot Frigate logs a
  one-time random `admin` password — find it with
  `journalctl -u frigate | grep -i password`. Log in, then set your own password under
  Settings → Users (it persists in `/var/lib/frigate/frigate.db`).

_WireGuard peer devices connect to `home.blaix.com:51820` using configs kept in
1Password / each device's WireGuard app (the server key itself is sops-managed, above)._

### pippinix (decommissioned home server)

* `sudo smbpasswd -a justin` — Samba share password.

### blaixapps (remote server)

These files must exist on the server and are not managed by nix _(TODO: migrate to
[sops](/SECRETS.md))_:

* **`/etc/grafana-admin-password`** — Grafana `admin` user password:
  ```bash
  echo 'your-secure-password' | sudo tee /etc/grafana-admin-password
  sudo chown grafana:grafana /etc/grafana-admin-password
  sudo chmod 0600 /etc/grafana-admin-password
  ```
* **`/etc/grafana-secret-key`** — key Grafana uses to sign cookies / encrypt data:
  ```bash
  nix run nixpkgs#openssl -- rand -hex 32 | sudo tee /etc/grafana-secret-key
  sudo chown grafana:grafana /etc/grafana-secret-key
  sudo chmod 0600 /etc/grafana-secret-key
  ```
* **`/etc/htpasswd`** — nginx basic-auth file fronting several of my personal apps:
  ```bash
  nix-shell -p apacheHttpd
  sudo htpasswd -c /etc/htpasswd <username>
  ```

### Planned (not yet built)

* **pippinix restic backups**: a restic repo password + Backblaze B2 env, both via sops
  (`secrets/pippinix.yaml`), plus `sudo smbpasswd -a` for the `arwen`/`bilbo` SMB users.
  See [`TODO-storage-backup-plan.md`](/TODO-storage-backup-plan.md).

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

#### Torrents and Jellyfin

There's some manual setup required if you're going to use this mac to download
media. See [`hosts/mac/proton-portforward.nix`](hosts/mac/proton-portforward.nix).

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
  You can base it on one of the other files in that directory.
  If you're using an apple silicon mac, you should base it on `pippinix.nix`.
  `shire.nix` is a good reference for a home server setup (Jellyfin, SMB share, mDNS, WireGuard).
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

* Set a password for your user (as root):

  ```
  passwd justin
  ```

* Register this host as a sops-nix secret recipient (see [SECRETS.md](/SECRETS.md)). Skip if this host doesn't need any secrets yet.

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

See the blaixapps entry under [Secrets and passwords](#secrets-and-passwords) for the
`/etc/grafana-admin-password`, `/etc/grafana-secret-key`, and `/etc/htpasswd` files this
server needs.

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

1. [Install nix](https://github.com/DeterminateSystems/nix-installer) (or [lix](https://lix.systems/install/)).

2. Clone this repo: 

  ```
  nix --extra-experimental-features nix-command --extra-experimental-features flakes run nixpkgs#git clone git@github.com:blaix/homer.git && cd homer
  ```
  
3. Choose a host name for your mac.
   Make sure it has a definitionn under `darwinConfigurations` in [`flake.nix`](/flake.nix) pointing to a `[hostname].nix` file under [`hosts/mac`](/hosts/mac).

4. Run the following, replacing `[hostname]` with the name from the previous step (e.g. `.#arwen`):

  ```
  nix --extra-experimental-features nix-command --extra-experimental-features flakes run nix-darwin -- switch --flake .#[hostname]
  ```

5. If you are me: Import my gpg key from 1Password.

### NixOs VM

1. You can create a nixos vm on mac with [orbstack](https://orbstack.dev/) (installed via configs in this repo) with:

  ```
  orb create nixos
  ```

2. Log in to your nixos vm.

  ```
  ssh orb
  ```

3. Start a shell with `git` available:

  ```
  nix-shell -p git
  ```
  
4. Clone this repo:

  ```
  git clone git@github.com:blaix/homer.git && cd homer
  ```

5. Choose a host name.
   Make sure it has a definitionn under `nixosConfigurations` in [`flake.nix`](/flake.nix) pointing to a `[hostname].nix` file under [`hosts/nixos`](/hosts/nixos).

6. Run the following, replacing `[hostname]` with the name from the previous step (e.g. `.#orb`):
  
  ```
  sudo nixos-rebuild switch --impure --flake .#orb
  ```

7. If you are me: Import my gpg key from 1Password.

### NixOs Server

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

7. Deploy the full config and applications: `just deploy-blaixapps`


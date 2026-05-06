# Secrets (sops-nix)

Secrets are encrypted in this repo using [sops-nix](https://github.com/Mic92/sops-nix) with [age](https://age-encryption.org/) keys.
Encrypted files live under [`secrets/`](/secrets).
Recipients are managed in [`.sops.yaml`](/.sops.yaml).

Each NixOS host decrypts its own secrets at activation using its existing `/etc/ssh/ssh_host_ed25519_key` as an age identity.
My personal age key (kept in 1Password) is the editor identity used to add and update secrets.

## One-time setup (if machine can edit secrets)

1. Pull my age private key from 1Password (item: **homer sops age key**) and write it to `~/.config/sops/age/keys.txt`:
   ```
   mkdir -p ~/.config/sops/age
   chmod 700 ~/.config/sops/age
   # paste private key into keys.txt
   chmod 600 ~/.config/sops/age/keys.txt
   ```
   First time ever (no key in 1Password yet)?
   Generate with `age-keygen -o ~/.config/sops/age/keys.txt`, save **both** halves to 1Password, then paste the public key into `.sops.yaml` (the value of `&justin`) and run `sops updatekeys secrets/*.yaml`.

2. Verify: `sops secrets/<any-file>.yaml` should open the decrypted contents in your editor.

## Register a new host as a recipient

Do this once per host, after the host has booted at least once (so its SSH host key exists), and before declaring any `sops.secrets.*` for that host.

1. Get the host's age public key:
   ```
   ssh <host> "cat /etc/ssh/ssh_host_ed25519_key.pub" | nix run nixpkgs#ssh-to-age
   ```

2. Edit [`.sops.yaml`](/.sops.yaml):
   - Copy the `keys` entry template and replace the `REPLACE_WITH...` placeholder with the value from step 1.
   - Add or update a `creation_rules` entry for `secrets/<host>.yaml` listing the host anchor + `*justin`.

3. Re-encrypt any existing files this host needs to read so the new recipient takes effect:
   ```
   sops updatekeys secrets/<file>.yaml
   ```

4. Commit and push.

## Add or edit a secret

```
sops secrets/<host>.yaml
```

Opens an editor on the decrypted contents. New files are created encrypted to whatever recipients `creation_rules` says.

Reference a secret from a NixOS module:

```nix
{ config, ... }:
{
  sops.secrets.restic-password = {
    sopsFile = ../../secrets/pippinix.yaml;
    # owner = "restic"; mode = "0400";  # defaults to root:root 0400
  };

  services.restic.backups.local = {
    passwordFile = config.sops.secrets.restic-password.path;
    # ...
  };
}
```

## Rotate or remove recipients

After editing the recipient list in `.sops.yaml`:
```
sops updatekeys secrets/<file>.yaml
```

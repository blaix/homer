# Pippinix storage + backup

## Context

`pippinix` (NixOS, aarch64-linux, Apple Silicon Mac mini, dual-boots macOS) currently serves no files. The goal is to turn it into a small home file server for the other Macs (arwen, bilbo) and the iPad, reachable on LAN and via the existing WireGuard `wg0`. Three workloads:

1. **Time Machine** destination for arwen + bilbo (over SMB).
2. **Shared general-purpose storage** at `/mnt/storage`, exported over SMB.
3. **Backups of the storage share** — a local copy on a separate USB drive, plus an offsite copy at Backblaze B2.

Building blocks already in place: `services.avahi` advertises `pippinix.local`, WireGuard `wg0` (10.100.0.1/24) is in `networking.firewall.trustedInterfaces`, and sops-nix is wired into all NixOS hosts but has no secrets yet. No existing Samba, restic, or external-storage config — verified by exploration.

Architecture (agreed earlier in conversation, not revisited): ext4 on three separate USB drives (no ZFS/no mergerfs — USB is fragile for ZFS, and a pool adds operational complexity that isn't justified here). One restic password used for both repos; B2 credentials via sops env file. Drive selection and formatting are operator-driven (which physical drive becomes which volume is the user's call).

## Critical files

- `hosts/nixos/pippinix.nix` — all new config goes here (single-file-per-host convention)
- `.sops.yaml` — replace `REPLACE_WITH_PIPPINIX_AGE_PUBLIC_KEY` and `REPLACE_WITH_PERSONAL_AGE_PUBLIC_KEY`
- `secrets/pippinix.yaml` — created via `sops`, holds restic password + B2 env
- `README.md` — add a "Pippinix storage operations" section for manual steps
- `SECRETS.md` — already covers the sops bootstrap; reference it from the new README section

## Drive layout (three ext4 partitions, identified by label)

| Label                  | Mount               | Purpose                            | Suggested size  |
|------------------------|---------------------|------------------------------------|-----------------|
| `pippinix-timemachine` | `/mnt/timemachine`  | TM destination for arwen + bilbo   | large           |
| `pippinix-storage`     | `/mnt/storage`      | Shared general-purpose files       | per user need   |
| `pippinix-backup`      | `/mnt/backup`       | restic local repo (mirrors storage)| ≥ storage drive |

Per user direction, the plan does **not** wipe or repartition any drive automatically. The README addition documents the steps; the operator runs them after carefully identifying each device with `lsblk -o NAME,SIZE,MODEL,LABEL,FSTYPE`. Steps per drive:

```
sudo wipefs -a /dev/sdX
sudo parted /dev/sdX -- mklabel gpt
sudo parted /dev/sdX -- mkpart primary ext4 1MiB 100%
sudo mkfs.ext4 -L pippinix-<role> /dev/sdX1
```

`fileSystems` entries in `pippinix.nix` use `/dev/disk/by-label/...` so device renumbering is harmless. Mount options: `nofail`, `noatime`, `x-systemd.device-timeout=10s` (boot won't hang on a missing drive; halves write IOPS; fails fast).

Per-Mac Time Machine cap (`fruit:time machine max size`) is intentionally **omitted** for now per user choice; can be added later as a one-line per-share setting.

## Samba

Single `services.samba` block with two shares:

- **`storage`** — `valid users = arwen bilbo justin`, `force group = smbshare`, masks `0664`/`2775`.
- **`timemachine`** — `valid users = arwen bilbo`, `fruit:time machine = yes`, `fruit:locking = none`. Per-Mac sub-directories `/mnt/timemachine/{arwen,bilbo}` owned `0700`.

Global flags: `min protocol = SMB3`; `server smb encrypt = desired` (TM has historic problems with mandatory encryption); `vfs objects = catia fruit streams_xattr`; Apple-fruit defaults (`fruit:metadata = stream`, `fruit:posix_rename = yes`, etc.); `hosts allow = <LAN_CIDR> 10.100.0.0/24 127.0.0.1`, `hosts deny = 0.0.0.0/0`. `nmbd.enable = false` (modern Macs use mDNS).

Disable Samba's built-in `openFirewall`; instead extend `networking.firewall.allowedTCPPorts` with `445` and `allowedUDPPorts` with `5353` (mDNS).

**Users** — declare `users.users.{arwen,bilbo}` declaratively with stable UIDs 1100/1101, group `smbshare`, no interactive shell. Add `justin` to `smbshare`. SMB passwords are set with `smbpasswd -a` (not declarative) — documented in README addition.

**LAN CIDR discovery** — run on pippinix:
```
ip -4 -o addr show scope global | awk '{print $2, $4}'
```
The output is `<interface> <ip>/<prefix>`; the CIDR is `<network>/<prefix>` (e.g. if you see `eth0 192.168.1.42/24`, the CIDR is `192.168.1.0/24`). Plug that into `hosts allow`.

## Avahi service advertising

Extend the existing `services.avahi` block:
- `publish.userServices = true`
- `extraServiceFiles.smb` — advertises `_smb._tcp` on 445 so Finder shows pippinix in Network.
- `extraServiceFiles.timemachine` — advertises `_adisk._tcp` with TXT records `sys=waMa=0,adVF=0x100` and `dk0=adVN=timemachine,adVF=0x82`, plus `_device-info._tcp` with `model=TimeCapsule8,119` for the TM icon in Finder.

mDNS is link-local; off-LAN Macs over WG won't auto-discover. They mount manually as `smb://10.100.0.1/storage` (or `/timemachine`). Documented in README only — no reflector setup.

## restic backups (two definitions)

Both share `paths = [ "/mnt/storage" ]`, `passwordFile = config.sops.secrets.restic-password.path`, `initialize = true`, `extraBackupArgs = [ "--exclude-caches" "--one-file-system" ]`, and `pruneOpts = [ "--keep-daily 7" "--keep-weekly 4" "--keep-monthly 12" "--keep-yearly 3" ]`.

- `services.restic.backups.local` — `repository = "/mnt/backup/restic"`, `OnCalendar = "*-*-* 02:00:00"`, `RandomizedDelaySec = "30m"`, `Persistent = true`.
- `services.restic.backups.b2` — `repository = "b2:pippinix-restic:/pippinix"`, additionally `environmentFile = config.sops.secrets.restic-b2-env.path`, `OnCalendar = "*-*-* 03:00:00"`, otherwise identical.

Native `b2:` backend (not `s3:`) — fewer API calls, simpler creds. B2 application key scoped to the single bucket, capabilities `listAllBucketNames listBuckets listFiles readFiles writeFiles deleteFiles` only. Set a B2 bucket storage cap + alert email out-of-band so a runaway repo can't run up a bill — documented in README, not in nix.

## sops-nix secrets

`secrets/pippinix.yaml` (encrypted; created via `sops secrets/pippinix.yaml`):

```yaml
restic-password: "<openssl rand -hex 32>"
restic-b2-env: |
  B2_ACCOUNT_ID=<keyID from B2>
  B2_ACCOUNT_KEY=<applicationKey from B2>
```

In `pippinix.nix`:
```nix
sops.secrets.restic-password = {
  sopsFile = ../../secrets/pippinix.yaml;
  mode = "0400";
};
sops.secrets.restic-b2-env = {
  sopsFile = ../../secrets/pippinix.yaml;
  mode = "0400";
};
```
restic systemd units run as root; default owner root:root is correct.

## Bootstrap order (must be done in sequence)

1. Personal age private key in place at `~/.config/sops/age/keys.txt` (already done per `SECRETS.md`); paste its public half into `.sops.yaml` `&justin`.
2. `ssh pippinix "cat /etc/ssh/ssh_host_ed25519_key.pub" | nix run nixpkgs#ssh-to-age` — paste output into `.sops.yaml` `&pippinix`.
3. Create B2 bucket `pippinix-restic` + scoped application key in B2 web UI.
4. `openssl rand -hex 32` for the restic password. `sops secrets/pippinix.yaml`, populate `restic-password` and `restic-b2-env`. Commit `.sops.yaml` + `secrets/pippinix.yaml`.
5. Discover LAN CIDR with the command above; record for next step.
6. Format the three USB drives with the documented `wipefs`/`parted`/`mkfs.ext4 -L` sequence; verify with `lsblk`.
7. Add `fileSystems."/mnt/{timemachine,storage,backup}"` to `pippinix.nix`. `just switch pippinix`. Confirm `df -h` shows all three.
8. Add Samba + Avahi `extraServiceFiles` + `users.users.{arwen,bilbo}` + `users.groups.smbshare` + firewall port additions to `pippinix.nix`. `just switch pippinix`. Then on pippinix: `sudo smbpasswd -a justin && sudo smbpasswd -a arwen && sudo smbpasswd -a bilbo`. Create directory layout:
    ```
    sudo install -d -o root  -g smbshare -m 2775 /mnt/storage
    sudo install -d -o arwen -g arwen    -m 0700 /mnt/timemachine/arwen
    sudo install -d -o bilbo -g bilbo    -m 0700 /mnt/timemachine/bilbo
    ```
9. Add `sops.secrets.*` and `services.restic.backups.{local,b2}` to `pippinix.nix`. `just switch pippinix`.
10. Manual first runs: `sudo systemctl start restic-backups-local.service` then `restic-backups-b2.service`. Tail with `journalctl -u`.
11. Add a "Pippinix storage operations" section to `README.md` covering: drive formatting commands, `smbpasswd` setup, mount paths, B2 bucket configuration tips (caps, key scope), restore drill, and how to add a Mac (declare user → set smbpasswd → grant TM access).

## Verification

After bootstrap completes:

- `df -h | grep /mnt` shows the three mounts. Reboot pippinix and re-verify (proves `nofail` + by-label addressing works).
- On pippinix: `avahi-browse -rt _adisk._tcp` lists pippinix with `dk0=adVN=timemachine,adVF=0x82`.
- From arwen or bilbo: `smb://pippinix.local` in Finder shows `storage` and `timemachine`. Mount storage, write a file, verify it lands at `/mnt/storage` on pippinix.
- System Settings → General → Time Machine → Add Backup Disk shows "pippinix - timemachine". Run a small initial backup (cancel after a few GB).
- `systemctl status restic-backups-local.timer restic-backups-b2.timer` — both `active (waiting)`.
- After step 10 first runs: `sudo restic -r /mnt/backup/restic -p /run/secrets/restic-password snapshots` lists ≥1 snapshot. Same for b2 repo (or just confirm the systemd unit `Result=success`).
- **Restore drill**: create `/mnt/storage/restore-test.txt`, force `restic-backups-local.service`, delete the file, restore via `restic restore latest --target / --include /mnt/storage/restore-test.txt` from both repos. Mark this as a recurring 6-month TODO.

## Risks and known gotchas

- **USB bus disconnect mid-write** — ext4 gets remounted RO, restic unit fails, Samba clients see I/O errors. Recovery: `umount`/`mount`. Mitigation: prefer self-powered drives (3.5" externals) over bus-powered ones sharing a hub.
- **No backup-failure alerting** — out of scope here; future TODO. Cheapest win: a healthchecks.io ping in `backupCleanupCommand`. Eventually wire into the Prometheus stack already on blaixapps.
- **B2 bill spikes** — runaway `/mnt/storage` growth → next b2 run uploads everything. Set bucket storage + bandwidth caps in B2 UI. Do **not** set B2 lifecycle rules — they fight restic's own retention.
- **`fruit:time machine max size` deliberately omitted** — TM can fill the drive over time. Operator monitors `df`; add cap later if needed.
- **SMB passwords are not declarative** — re-entered after a rebuild from scratch. Acceptable for personal infra.
- **mDNS doesn't traverse WG** — off-LAN Macs mount by IP; documented, not solved.
- **Activation fails if sops references can't decrypt** — verify `sops -d secrets/pippinix.yaml` works before `just switch pippinix` in step 9.

## Out of scope (deferred)

- Per-user Time Machine size caps
- Backup failure notifications
- UPS for the Mac mini
- Migrating the existing hand-managed `/etc/grafana-*` server secrets on blaixapps to sops-nix
- Drive pooling (mergerfs / ZFS) — only revisit if a single drive becomes insufficient
- mDNS reflector for Bonjour-over-WG

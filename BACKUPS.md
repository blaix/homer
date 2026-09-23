# Backups

## Current

* **`/mnt/storage` → pippin** — nightly restic push from shire at 03:00 to
  `/Volumes/backup/restic-storage` on pippin, over SFTP. Declared as
  `services.restic.backups.storage` in
  [`hosts/nixos/shire.nix`](/hosts/nixos/shire.nix); retention is 7 daily / 4 weekly /
  12 monthly. Restore with the `restic-storage` wrapper on shire.

  This is **redundancy, not a backup**: one drive, same house, ageing HFS+. The B2 tier
  below is what makes it a real backup.

## TODO

- [ ] mv anything that's not pure media (e.g. home movies) out of /mnt/media
    - [x] /mnt/storage exists (the old 1TB drive, whole-disk ext4, label "storage")
- [ ] backblaze b2 remote backup
    - [ ] pre-encrypted by restic - store private key in 1Pass
    - [ ] /mnt/media
    - [ ] /mnt/storage — add as a second `services.restic.backups.*` entry beside
          `storage`, or `restic copy` from the pippin repo so the two tiers share
          snapshot history
- [ ] Decide what to do about /mnt/media. It will not fit alongside /mnt/storage on
      pippin's drive (1.1T used vs 1.6T free, before any history), so it needs either
      its own target or B2 only.
- [ ] Any other private keys or credentials that live on homer that should backed up to 1Pass?
- [ ] Figure out backup plan for Photos (the whole family?). Might use mac mini.

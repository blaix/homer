# USB drive recommendations for pippinix media library

For an always-on media library, want a **NAS-class CMR drive** (Conventional
Magnetic Recording — avoid SMR, which thrashes badly under torrent seeding +
media use).

## Options

1. **WD Red Plus 8–12 TB in a USB enclosure** — explicitly CMR, designed for
   24/7 operation. ~$150–250 for the bare drive plus ~$25–40 for a good USB 3
   enclosure (OWC Mercury Elite Pro or StarTech are well-tested on Mac). Best
   longevity per dollar, and the drive can be swapped later without buying a
   new enclosure.
2. **Seagate IronWolf 8–16 TB in an enclosure** — equivalent NAS-class tier to
   WD Red Plus, similar price; pick whichever is cheaper on the day.
3. **WD Elements / My Book 12–18 TB external (pre-enclosed)** — cheapest per
   TB, single unit, USB 3. The drive inside is *usually* a WD Red but varies
   by batch (some buyers "shuck" them to confirm). Lower up-front cost,
   slightly more uncertainty about the internals; fine for a single-drive
   use case where buying another if it dies is acceptable.

## Things to verify when buying

- **CMR, not SMR.** Manufacturers hide this; cross-reference the model number
  against community lists (r/DataHoarder has good ones). WD Red Plus and
  IronWolf are CMR; "WD Red" (without "Plus") was infamously SMR for a while.
- **External power.** 3.5" drives need a wall wart — fine for a server, just
  plan an outlet.
- **USB-A interface on the enclosure** is generally safer than USB-C on older
  hosts; pippinix's Mac mini handles both fine, so either works.
- **Format ext4 on first connect** — match the `/mnt/music` pattern in
  `hosts/nixos/pippinix.nix` (`device = "/dev/disk/by-label/media"`).

## Capacity

8 TB is a comfortable starting point for movies + TV; 12+ TB if building a
real library. Music is small enough to ignore in the budgeting.

## Migration

When the drive arrives, swap `/mnt/media` on root for a `fileSystems."/mnt/media"`
block in `hosts/nixos/pippinix.nix` mirroring the existing music one.

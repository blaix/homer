- [X] Switch to a Flakes setup
- [X] Use Mae's gren-treesitter (officially added to the nvim-treesitter plugin)
- [X] Remove duplication under the various hosts/ files. Especially with my user setup.
- [.] Set up shire as a router for cameras (Frigate + Home Assistant)
    - [x] Camera subnet on enp3s0 (eno1 stays on the LAN; dual wired NICs, no wifi needed)
    - [ ] Cable the Reolink PoE switch + cameras, then pin their IPs (Kea reservations)
- [ ] Migrate blaixapps hand-managed secrets to sops-nix (shire is already done)
- [ ] See TODO comments in code.

Maybe:

- [ ] Switch to Lix? https://lix.systems/add-to-config/#flake-based-configurations
- [ ] Try https://flake.parts/
- [ ] Consider/try snowfall lib
- [ ] Better documentation
- [ ] anything I can do about how slow it is?

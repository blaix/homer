#!/usr/bin/env bash

set -e

sudo nix-channel --add https://github.com/nix-community/home-manager/archive/release-23.05.tar.gz home-manager
sudo nix-channel --update
sudo nixos-rebuild -I nixos-config=configuration.nix switch

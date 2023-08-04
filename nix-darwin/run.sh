#!/usr/bin/env bash

set -e

# sudo nix-channel --add https://github.com/nix-community/home-manager/archive/release-23.05.tar.gz home-manager
# sudo nix-channel --update
darwin-rebuild -I darwin-config=darwin-configuration.nix switch

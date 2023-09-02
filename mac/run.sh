#!/usr/bin/env bash

set -e

if [[ -z "$HOST" ]]; then
    echo "Must set HOST variable" 1>&2
    exit 1
fi

darwin-rebuild -I darwin-config=darwin-configuration.nix switch

# Install homebrew. Using this for casks, and there's no nixpkg.
if [ ! -f "/opt/homebrew/bin/brew" ]; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

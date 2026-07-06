{ pkgs }:

# rwhat: explain what a given rsync command will do. Replace `rsync` with
# `rwhat` in a command and it prints a one-line description of each flag
# (expanding nested/aliased flags too), so you don't have to dig through
# rsync's man page. See https://codeberg.org/bit101/rwhat
pkgs.buildGoModule {
  pname = "rwhat";
  version = "unstable-2024-06-13";

  src = pkgs.fetchgit {
    url = "https://codeberg.org/bit101/rwhat.git";
    rev = "1a18a637a9f0a8d6fea04070ef82f20d70299392";
    hash = "sha256-vJX1IYCYj/xieIM6hmwewuQoNxMOUvAmA61Ao+ddftw=";
  };

  # No external dependencies (go.mod has no require block).
  vendorHash = null;

  # Only build the CLI; ./gen is a `//go:build ignore` code generator.
  subPackages = [ "." ];

  meta = {
    description = "Explain what a given rsync command will do";
    homepage = "https://codeberg.org/bit101/rwhat";
    license = pkgs.lib.licenses.mit;
    mainProgram = "rwhat";
  };
}

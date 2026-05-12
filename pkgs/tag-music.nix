{ pkgs }:

pkgs.writers.writePython3Bin "tag-music" {
  libraries = with pkgs.python3Packages; [ mutagen requests ];
  flakeIgnore = [ "E501" "W503" "E203" "E402" ];
} (builtins.readFile ./tag-music.py)

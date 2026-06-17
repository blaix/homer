{ pkgs }:

let
  unwrapped = pkgs.writers.writePython3Bin "tag-music" {
    libraries = with pkgs.python3Packages; [ mutagen requests ];
    flakeIgnore = [ "E501" "W503" "E203" "E402" ];
  } (builtins.readFile ./tag-music.py);
in
pkgs.symlinkJoin {
  name = "tag-music";
  paths = [ unwrapped ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/tag-music \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.rsgain ]}
  '';
}

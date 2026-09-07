{ pkgs }:

# provision-camera: configure a new Amcrest/Dahua PoE camera for the Frigate
# stack over its HTTP CGI API - set the shared admin password from sops and pin
# a static IP - so adding a camera is one script run plus one line in
# hosts/nixos/cameras.nix. See that file for how the camera subnet is laid out
# and why there is no DHCP server on it.
pkgs.writeShellApplication {
  name = "provision-camera";
  runtimeInputs = with pkgs; [ curl sops coreutils gnugrep ];
  text = builtins.readFile ./provision-camera.sh;
}

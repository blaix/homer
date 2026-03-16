{ pkgs, inputs, ... }:
{
  imports = [
    # THIS MACHINE WAS SET UP USING:
    # https://github.com/nix-community/nixos-apple-silicon/blob/main/docs/uefi-standalone.md#uefi-preparation
    # Below is the machine-specific config set up by that process:
    /etc/nixos/configuration.nix
    # And here aremy own common nixos configs applied on top of it:
    ./common.nix
  ];

  networking.hostName = "pippinix";

  # Enable my wired USB keyboard during boot
  boot.initrd.availableKernelModules = [ "hid-generic" ];

  # mDNS so this machine is reachable as pippinix.local
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  # Justin user configuration
  users.groups.justin = {};
  users.users.justin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    group = "justin";
    openssh.authorizedKeys.keys = import ../../users/justin/ssh-keys.nix;
  };

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
    };
  };
}


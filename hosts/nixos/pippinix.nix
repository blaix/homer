{ pkgs, apple-silicon, ... }:
{
  imports = [
    /etc/nixos/configuration.nix
    apple-silicon.nixosModules.default
    ./common.nix
  ];

  networking = {
    computerName = "pippinix";
    hostName = "pippinix";
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


{ pkgs, lib, ... }:
{
  imports = [
    /etc/nixos/hardware-configuration.nix
    # Use the local apple-silicon-support module placed by the Asahi installer
    # instead of the nixos-apple-silicon flake input. The flake's main branch
    # ships kernel 6.18.x which has a udevd hang on this hardware. The local
    # module has the known-working kernel 6.17.7.
    /etc/nixos/apple-silicon-support
    ./common.nix
  ];

  networking.hostName = "pippinix";
  networking.networkmanager.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  system.stateVersion = "25.11";

  # Enable my wired USB keyboard during boot
  boot.initrd.availableKernelModules = [ "hid-generic" ];

  # The local apple-silicon-support module builds linux-asahi 6.17.7, which
  # doesn't have CONFIG_NOVA_CORE. nixpkgs sets NOVA_CORE as a required kernel
  # config option, causing a build error. This makes it optional (warning
  # instead of error). See nixos-apple-silicon issue #427.
  boot.kernelPatches = [{
    name = "fix-nova-core";
    patch = null;
    structuredExtraConfig = with lib.kernel; {
      NOVA_CORE = lib.mkForce (option no);
    };
  }];

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

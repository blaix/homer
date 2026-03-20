{ pkgs, lib, ... }:
{
  imports = [
    # Use the hardware-config placed here by the Asahi installer:
    /etc/nixos/hardware-configuration.nix

    # Use the apple-silicon-support module placed here by the Asahi installer.
    # Specifically *not* using the nixos-apple-silicon flake as I originally
    # intended. Its main branch ships kernel 6.18.x which hangs on boot on this
    # hardware. The module from the installer has the known-working kernel 6.17.7:
    /etc/nixos/apple-silicon-support

    # My personal configs:
    ./common.nix
  ];

  system.stateVersion = "25.11";

  networking.hostName = "pippinix";
  networking.networkmanager.enable = true;

  # Copied from the original /etc/configruation.nix
  # Set according to the nixos-apple-silicon instructions at:
  # https://github.com/nix-community/nixos-apple-silicon/blob/2fbdf62451bcd9fc83ca99c56a6e379df8c47c8d/docs/uefi-standalone.md#nixos-configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  # Enable my wired USB keyboard during boot (still not working)
  boot.initrd.availableKernelModules = [ "hid-generic" ];

  # The local apple-silicon-support module builds linux-asahi 6.17.7 (see imports above),
  # which doesn't have CONFIG_NOVA_CORE. nixpkgs sets NOVA_CORE as a required kernel
  # config option, causing a build error. This makes it optional (warning
  # instead of error). See nixos-apple-silicon issue #427.
  boot.kernelPatches = [{
    name = "fix-nova-core";
    patch = null;
    structuredExtraConfig = with lib.kernel; {
      NOVA_CORE = lib.mkForce (option no);
    };
  }];

  # Compressed RAM swap - faster than disk swap, provides a buffer before OOM
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # WireGuard VPN server
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.1/24" ];
    listenPort = 51820;
    generatePrivateKeyFile = true;
    privateKeyFile = "/etc/wireguard/wg0-key";

    peers = [
      { # arwen
        publicKey = "DnDZDE3WEygq58ak+ViZyRyp1sadqRKSmtoL25ztxiY=";
        allowedIPs = [ "10.100.0.2/32" ];
      }
      { # bilbo
        publicKey = "doShLIrZi005B0qsO8aLY4gF06gHSiv4Hw3YmnIe3Co=";
        allowedIPs = [ "10.100.0.3/32" ];
      }
    ];
  };

  # Firewall - allow SSH, local dev server, and WireGuard, trust VPN interface
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 3000 ];
    allowedUDPPorts = [ 51820 ];
    trustedInterfaces = [ "wg0" ];
  };

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

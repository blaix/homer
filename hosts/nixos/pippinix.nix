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

  # Firewall - allow SSH and WireGuard, trust VPN interface
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
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

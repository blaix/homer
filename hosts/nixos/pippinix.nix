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
  time.timeZone = "America/New_York";

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

  # Workaround for nixos-apple-silicon#449: nixpkgs' default of 33 is
  # rejected by this 16K-page kernel. 31 is the value for ARM64_16K_PAGES.
  # See https://github.com/nix-community/nixos-apple-silicon/issues/449
  boot.kernel.sysctl."vm.mmap_rnd_bits" = lib.mkForce 31;

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
      { # ipad
        publicKey = "j+PtMQZe4IBzTOjSCFeknomeeEZXAYd4rhfrX+GQJRQ=";
        allowedIPs = [ "10.100.0.4/32" ];
      }
    ];
  };

  # Firewall - allow SSH, local dev servers, Jellyfin (web + LAN auto-discovery),
  # and WireGuard, trust VPN interface
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 3000 8000 8096 ];
    allowedUDPPorts = [ 51820 7359 ];
    trustedInterfaces = [ "wg0" ];
  };

  # Jellyfin music server. Reachable on the LAN (8096) and from wg peers
  # (10.100.0.1:8096). UDP 7359 is opened above so LAN clients like the Roku
  # Jellyfin app can auto-discover the server.
  services.jellyfin = {
    enable = true;
    openFirewall = false;
  };

  # Music library on dedicated USB drive (ext4, labeled "music").
  fileSystems."/mnt/music" = {
    device = "/dev/disk/by-label/music";
    fsType = "ext4";
    # nofail = server still boots if the drive is unplugged.
    options = [ "nofail" "x-systemd.device-timeout=10s" ];
  };
  systemd.tmpfiles.rules = [
    "d /mnt/music 2775 jellyfin jellyfin -"
  ];

  # SMB share for the music drive, reachable from Macs as smb://pippinix.local.
  #
  # First-time machine setup (not declarative):
  #   - sudo smbpasswd -a justin to set the Samba password
  #   - In Jellyfin's web UI, add a Music library pointing at /mnt/music
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "pippinix";
        "netbios name" = "pippinix";
        "security" = "user";
        # No anonymous access; we want auth so Finder caches creds in Keychain.
        "guest account" = "nobody";
        "map to guest" = "never";
      };
      music = {
        "path" = "/mnt/music";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "justin";
        "force group" = "jellyfin";
        "create mask" = "0664";
        "directory mask" = "2775";
      };
    };
  };

  # mDNS so this machine is reachable as pippinix.local
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      userServices = true;          # required for extraServiceFiles
    };
    # so pippinix appears in the Finder Network sidebar automatically:
    extraServiceFiles.smb = ''
      <?xml version="1.0" standalone='no'?>
      <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
      <service-group>
        <name replace-wildcards="yes">%h</name>
        <service>
          <type>_smb._tcp</type>
          <port>445</port>
        </service>
      </service-group>
    '';
  };

  # Justin user configuration
  users.groups.justin = {};
  users.users.justin = {
    isNormalUser = true;
    # `jellyfin` group lets justin write into /var/lib/jellyfin-media (see
    # tmpfiles rules above) without sudo, so music can be scp'd/rsync'd in
    # from another machine.
    extraGroups = [ "wheel" "jellyfin" ];
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

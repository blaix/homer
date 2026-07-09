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

  # Copied from the original /etc/configuration.nix
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

  # ---------------------------------------------------------------------------
  # Soft-decommissioned this as my home server on 2026-07-09. Moved to shire.
  # ---------------------------------------------------------------------------

  # Firewall - SSH only. (Samba opens 445 via its own openFirewall below.)
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ ];
  };

  # Enable mosh connections (opens UDP ports)
  programs.mosh.enable = true;

  # Old media drive (ext4, label "media"). 
  fileSystems."/mnt/media" = {
    device = "/dev/disk/by-label/media";
    fsType = "ext4";
    # nofail = server still boots if the drive is unplugged.
    options = [ "nofail" "x-systemd.device-timeout=10s" ];
  };

  # General-purpose documents on a second USB drive (ext4, labeled "documents").
  # Exported as an SMB share, reachable on the LAN. (Migration to shire deferred.)
  fileSystems."/mnt/documents" = {
    device = "/dev/disk/by-label/documents";
    fsType = "ext4";
    options = [ "nofail" "noatime" "x-systemd.device-timeout=10s" ];
  };

  # Drive dirs owned by justin, world-readable.
  systemd.tmpfiles.rules = [
    "d /mnt/media     0755 justin justin -"
    "d /mnt/documents 0755 justin justin -"
  ];

  # SMB share reachable from Macs as smb://pippinix.local (read-write).
  # First-time machine setup (not declarative): sudo smbpasswd -a justin.
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

        # macOS interop: store Mac metadata in ext4 xattrs instead of "._"
        # AppleDouble sidecar files, and auto-delete Finder/Spotlight junk.
        "vfs objects" = "catia fruit streams_xattr";
        "fruit:metadata" = "stream";
        "fruit:posix_rename" = "yes";
        "fruit:veto_appledouble" = "no";
        "fruit:wipe_intentionally_left_blank_rfork" = "yes";
        "fruit:delete_empty_adfiles" = "yes";
        "fruit:nfs_aces" = "no";
        "veto files" = "/.DS_Store/.Spotlight-V100/.Trashes/.TemporaryItems/.fseventsd/.apdisk/.AppleDB/.AppleDesktop/Network Trash Folder/Temporary Items/";
        "delete veto files" = "yes";
      };
      # General-purpose documents share on the "documents" USB drive.
      documents = {
        "path" = "/mnt/documents";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "justin";
        "force user" = "justin";
        "create mask" = "0644";
        "directory mask" = "0755";
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

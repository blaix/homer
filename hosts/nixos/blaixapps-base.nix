{ config, pkgs, lib, inputs, ... }:
{
  # ---------------------------------------------------------------------------
  #   Base hardened public-facing server configuration
  #   Suitable for use with nixos-anywhere
  #   Minimal config suitable for initial installation
  #   Import common.nix separately for full package set and configuration
  # ---------------------------------------------------------------------------

  imports = [
    inputs.disko.nixosModules.disko
  ];

  # Disko configuration based on official nixos-anywhere examples
  disko.devices = {
    disk.disk1 = {
      device = lib.mkDefault "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            name = "boot";
            size = "1M";
            type = "EF02";
          };
          esp = {
            name = "ESP";
            size = "500M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          root = {
            name = "root";
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [ "defaults" ];
            };
          };
        };
      };
    };
  };

  # Boot loader - disko will configure the device
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # Ensure initrd can find GPT partitions
  boot.initrd.availableKernelModules = [
    "ata_piix" "uhci_hcd" "virtio_pci" "virtio_blk" "virtio_scsi"
    "sd_mod" "sr_mod" "ahci"
  ];

  boot.initrd.kernelModules = [ ];

  # Nix settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "root" "justin" ];
  nixpkgs.config.allowUnfree = true;

  # Minimal packages for initial setup
  environment.systemPackages = with pkgs; [
    git
    vim
  ];

  # Justin user configuration
  users.groups.justin = {};
  users.users.justin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    group = "justin";
    openssh.authorizedKeys.keys = import ../../users/justin/ssh-keys.nix;
  };

  # Allow sudo without password for wheel group (required for deployments)
  security.sudo.wheelNeedsPassword = false;

  # SSH hardening
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
    };
  };

  # Enable DHCP for network connectivity
  networking.useDHCP = lib.mkDefault true;

  # Firewall with common web server ports
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22   # SSH
      80   # HTTP (redirects to HTTPS)
      443  # HTTPS
    ];
    allowedUDPPorts = [ ];
  };

  # Fail2Ban for SSH brute force protection
  services.fail2ban = {
    enable = true;
    maxretry = 5;
  };

  # System state version
  system.stateVersion = "25.05";
}

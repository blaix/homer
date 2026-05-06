{ pkgs, ... }:
{
  # ---------------------------------------------------------------------------
  #   Settings shared among all my NixOs systems
  # ---------------------------------------------------------------------------

  imports = [ ../common.nix ];

  users.defaultUserShell = pkgs.zsh;

  # Enable mosh, opens UDP ports 60000 ... 61000
  programs.mosh.enable = true;

  # sops-nix: each host decrypts its own secrets at activation using its
  # ed25519 SSH host key as an age identity. See SECRETS.md
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  environment.systemPackages = with pkgs; [
    sops        # edit/encrypt/decrypt secrets files
    ssh-to-age  # convert ssh ed25519 keys to age recipients
  ];
}

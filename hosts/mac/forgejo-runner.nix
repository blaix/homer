{ config, lib, pkgs, ... }:
# Forgejo Actions runner for git.blaix.com, running jobs directly on this Mac
# (host mode) for workflows with `runs-on: macos` (any Mac) or `runs-on: pippin`
# (this one). Its labels never overlap shire's, so jobs meant for shire, like
# deploys (`runs-on: shire`), can't land here.
#
# nix-darwin has no module for this, so it's a plain launchd daemon running as
# its own hidden user, _forgejo-runner. Like any launchd daemon, it can't touch
# removable volumes (TCC), so /Volumes/backup is out of its reach as long as
# it is never granted Full Disk Access.
#
# The registration token comes from sops (secrets/pippin.yaml, the same value
# as shire's), as the line TOKEN=<token>. The daemon registers as "pippin" on
# first start. Log: /var/lib/forgejo-runner/runner.log.
let
  user = "_forgejo-runner";
  # Not taken by macOS (system accounts use < 500 and mostly < 300) or by the
  # nixbld users (350+ on this machine, up to the low 380s).
  id = 450;
  dir = "/var/lib/forgejo-runner";
  labels = lib.concatStringsSep "," [ "macos:host" "pippin:host" ];
  tokenFile = config.sops.secrets.forgejo-runner-token.path;

  configFile = (pkgs.formats.yaml { }).generate "forgejo-runner.yaml" {
    log.level = "info";
    runner = {
      file = "${dir}/.runner";
      capacity = 1;
      timeout = "1h";
    };
    host.workdir_parent = "${dir}/work";
  };

  start = pkgs.writeShellScript "forgejo-runner-start" ''
    set -euo pipefail
    cd ${dir}

    # At boot this can start before sops has installed the secret; launchd
    # retries a minute later.
    if [ ! -s ${tokenFile} ]; then
      echo "No registration token at ${tokenFile} yet" >&2
      exit 1
    fi
    token=$(sed -n 's/^TOKEN=//p' ${tokenFile})

    # Re-register when the token or labels change, like shire's NixOS module.
    wanted=$(printf '%s\n%s\n' "$token" ${lib.escapeShellArg labels} | sha256sum | cut -d' ' -f1)
    if [ ! -e .runner ] || [ "$(cat .registration 2>/dev/null)" != "$wanted" ]; then
      rm -f .runner
      forgejo-runner register --no-interactive \
        --instance https://git.blaix.com \
        --token "$token" \
        --name pippin \
        --labels ${lib.escapeShellArg labels} \
        --config ${configFile}
      echo "$wanted" > .registration
    fi

    exec forgejo-runner daemon --config ${configFile}
  '';
in
{
  # Only used to register. After a token change, the runner re-registers the
  # next time the daemon starts.
  sops.secrets.forgejo-runner-token = {
    owner = user;
    group = user;
  };

  users.knownUsers = [ user ];
  users.knownGroups = [ user ];
  users.groups.${user} = {
    gid = id;
    description = "Forgejo Actions runner";
  };
  users.users.${user} = {
    uid = id;
    gid = id;
    home = dir;
    shell = "/usr/bin/false";
    isHidden = true;
    description = "Forgejo Actions runner";
  };

  # The home directory, created here rather than by createHome, which is
  # meant for /Users homes.
  system.activationScripts.postActivation.text = ''
    mkdir -p ${dir}
    chown ${user}:${user} ${dir}
    chmod 700 ${dir}
  '';

  launchd.daemons.forgejo-runner = {
    command = "${start}";
    # What jobs see on PATH. nodejs is for JavaScript actions such as
    # actions/checkout. The macOS system dirs come last, for tools like
    # xcrun once Swift projects use this runner.
    path = [
      config.nix.package
      pkgs.forgejo-runner
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.gawk
      pkgs.gitMinimal
      pkgs.gnused
      pkgs.nodejs
      "/usr/bin"
      "/bin"
      "/usr/sbin"
      "/sbin"
    ];
    environment.HOME = dir;
    serviceConfig = {
      UserName = user;
      GroupName = user;
      WorkingDirectory = dir;
      RunAtLoad = true;
      KeepAlive = true;
      # Retry once a minute (e.g. before the token is installed), not every 10s.
      ThrottleInterval = 60;
      StandardOutPath = "${dir}/runner.log";
      StandardErrorPath = "${dir}/runner.log";
    };
  };
}

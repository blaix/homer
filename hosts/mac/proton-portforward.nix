{ pkgs, ... }:
let
  # nixpkgs' libnatpmp on Darwin doesn't set the binary's rpath, so
  # natpmpc can't find its own dylib. Wrap it to set DYLD_LIBRARY_PATH.
  natpmpc = pkgs.writeShellScriptBin "natpmpc" ''
    export DYLD_LIBRARY_PATH=${pkgs.libnatpmp}/lib''${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}
    exec ${pkgs.libnatpmp}/bin/natpmpc "$@"
  '';

  # Proton VPN setup for qBittorrent.
  #
  # I only want to torrent while on a Proton P2P VPN. I also want to enable
  # port forwarding (required for seeding), which is available on proton's paid
  # plans, but not exposed through the mac app. So I'm tunneling through
  # wireguard. This all requires some manual, one-time setup:
  #
  #   1. Sign in at https://account.protonvpn.com -> Downloads -> WireGuard.
  #   2. Platform: pick "Router" (we want a raw .conf).
  #   3. Toggle "NAT-PMP (Port Forwarding)" ON (requires a paid account).
  #   4. Pick a "P2P/BitTorrent" server (double arrow?) (Switzerland?).
  #   5. Save to a .conf file (can be deleted when done).
  #   6. In the WireGuard app File -> Import Tunnel(s) from File.
  #
  # Now tell qBittorrent to only run when we're using the tunnel:
  #
  #   1. Start the wireguard tunnel so it's available in qbittorrent options.
  #   2. In qBittorrent -> Preferences -> Advanced:
  #      set "Optional IP address to bind to" = the `Address` value from
  #      the Proton .conf (e.g. 10.2.0.2).
  #
  # Now we need to keep qBittorrent updated with forwarded port (randomly
  # chosen by Proton). We do this by hitting the web api interface with the
  # below script, which also requires some manual setup:
  #   
  #   1. In qBittorrent -> Preferences -> Web UI:
  #        - Check "Web User Interface (Remote control)"
  #        - IP address: 127.0.0.1, Port: 8080
  #        - Check "Bypass authentication for clients on localhost"
  #          (this script posts to the API without logging in)
  #   2. In qBittorrent -> Preferences -> Connection:
  #        - Turn OFF "Use UPnP / NAT-PMP port forwarding from my router"
  #          (it would talk to the LAN router, not Proton's gateway)
  protonPortForward = pkgs.writeShellScript "proton-portforward" ''
    set -u
    GATEWAY=10.2.0.1
    NATPMPC=${natpmpc}/bin/natpmpc
    CURL=${pkgs.curl}/bin/curl
    QB_URL=http://127.0.0.1:8080
    last=""
    while true; do
      if out=$("$NATPMPC" -a 1 0 udp 60 -g "$GATEWAY" 2>/dev/null); then
        "$NATPMPC" -a 1 0 tcp 60 -g "$GATEWAY" >/dev/null 2>&1 || true
        port=$(printf '%s\n' "$out" | sed -n 's/.*Mapped public port \([0-9]*\).*/\1/p' | head -n1)
        if [ -n "$port" ] && [ "$port" != "$last" ]; then
          "$CURL" -fsS -X POST \
            --data-urlencode "json={\"listen_port\":$port}" \
            "$QB_URL/api/v2/app/setPreferences" >/dev/null 2>&1 || true
          last="$port"
        fi
      fi
      sleep 45
    done
  '';
in
{
  # natpmpc on PATH for manual testing/inspection.
  environment.systemPackages = [ natpmpc ];

  launchd.user.agents.proton-portforward = {
    serviceConfig = {
      ProgramArguments = [ "${protonPortForward}" ];
      RunAtLoad = true;
      KeepAlive = true;
    };
  };
}

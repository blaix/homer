{ pkgs, ... }:
let
  # Proton VPN over WireGuard hangs IPv6 connections on Mac: AAAA records
  # resolve but TCP SYN over IPv6 times out, so browsers stall in Happy
  # Eyeballs (~5s per new origin) and TLS handshakes appear to crawl, even
  # though bandwidth tests look great.
  #
  # This watcher detects the Proton tunnel by its assigned address (utun
  # device numbers vary) and toggles IPv6 on the Wi-Fi service to match.
  # Extend SERVICE if you need this on Ethernet too.
  ipv6Toggle = pkgs.writeShellScript "proton-ipv6-toggle" ''
    set -u
    NETWORKSETUP=/usr/sbin/networksetup
    IFCONFIG=/sbin/ifconfig
    SERVICE="Wi-Fi"

    last=""
    while true; do
      # Proton assigns 10.X.Y.2/32 to the client; match that on any utun.
      if "$IFCONFIG" | grep -qE 'inet 10\.[0-9]+\.[0-9]+\.2 '; then
        state="up"
      else
        state="down"
      fi

      if [ "$state" != "$last" ]; then
        if [ "$state" = "up" ]; then
          "$NETWORKSETUP" -setv6off "$SERVICE"
        else
          "$NETWORKSETUP" -setv6automatic "$SERVICE"
        fi
        last="$state"
      fi
      sleep 5
    done
  '';
in
{
  # System daemon (not user agent) because networksetup needs root.
  launchd.daemons.proton-ipv6-toggle = {
    serviceConfig = {
      ProgramArguments = [ "${ipv6Toggle}" ];
      RunAtLoad = true;
      KeepAlive = true;
    };
  };
}

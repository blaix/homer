{ config, pkgs, ... }:
{
  # ---------------------------------------------------------------------------
  #   Home camera stack: Frigate NVR + Home Assistant + Mosquitto, on an
  #   isolated camera subnet. See ~/dia/home/projects/Home Security Camera
  #   Setup.md for the overall plan.
  #
  #   Milestone: LIVE FEED ONLY. No object detection (no Coral) and no
  #   recording yet. Frigate restreams each camera for live viewing in its web
  #   UI and, via the Frigate<->HA integration, in the Home Assistant app
  #   (including remotely over WireGuard). Detection and recording are wired in
  #   later as small config flips - see the "Deferred" notes at the bottom.
  #
  #   First-time machine setup (not declarative):
  #     - Frigate UI (http://shire.local:8971): auth is ON by default. On the
  #       first successful boot Frigate creates an `admin` user and logs a
  #       one-time random password - find it with:
  #         journalctl -u frigate | grep -i password
  #       Log in as admin with that, then set your own password in the UI under
  #       Settings -> Users. It persists in /var/lib/frigate/frigate.db (survives
  #       restarts and is never re-logged). The UI is reachable by any device on
  #       the LAN, not just over WireGuard, which is why auth is kept on.
  #     - Home Assistant: open http://shire.local:8123 and create the admin
  #       account (onboarding). Then add two integrations from the HA UI:
  #         * MQTT     -> broker 127.0.0.1, port 1883
  #         * Frigate  -> URL http://127.0.0.1:5000
  #       The Frigate integration surfaces each camera as an HA entity.
  #     - HA companion app: install on the phone; on home WiFi it finds shire
  #       (http://shire.local:8123). Remotely, connect WireGuard and use
  #       http://10.100.0.1:8123.
  #     - Camera RTSP password: managed via sops (secrets/shire.yaml). Set the
  #       same password on each camera's admin account when provisioning them.
  #     - Camera IPs: discover each camera's MAC and add a Kea reservation - see
  #       the markdown doc's "Assign a camera a fixed IP" section.
  # ---------------------------------------------------------------------------

  # --- Camera subnet on the second NIC (enp3s0 -> Reolink PoE switch) ---------
  #
  # eno1 stays on the LAN (NetworkManager/DHCP, 192.168.7.x). enp3s0 becomes the
  # gateway for a dedicated camera subnet. NetworkManager must leave it alone so
  # the static address below sticks.
  networking.networkmanager.unmanaged = [ "interface-name:enp3s0" ];
  networking.interfaces.enp3s0.ipv4.addresses = [
    { address = "192.168.20.1"; prefixLength = 24; }
  ];

  # Cameras have no internet path: shire never forwards their traffic. This is
  # already the kernel default; pinned so the isolation can't silently regress.
  # If IP forwarding is ever enabled (e.g. WireGuard -> LAN routing), add an
  # explicit drop for saddr 192.168.20.0/24 in networking.firewall.extraForwardRules.
  boot.kernel.sysctl."net.ipv4.ip_forward" = 0;

  # DHCP for the camera subnet. Cameras stay on DHCP (their factory default);
  # each gets a fixed IP via a MAC reservation below. See the markdown doc for
  # how to discover a camera's MAC and add its reservation.
  services.kea.dhcp4 = {
    enable = true;
    settings = {
      interfaces-config.interfaces = [ "enp3s0" ];
      lease-database = {
        type = "memfile";
        persist = true;
        name = "/var/lib/kea/dhcp4.leases";
      };
      subnet4 = [
        {
          id = 1;
          subnet = "192.168.20.0/24";
          pools = [ { pool = "192.168.20.100 - 192.168.20.200"; } ];
          # No routers option on purpose: cameras get no default gateway, so
          # they cannot even attempt to route out. Frigate reaches them
          # on-subnet from 192.168.20.1 regardless.
          reservations = [
            # Fill in once each camera's MAC is known (see markdown doc):
            # { hw-address = "aa:bb:cc:dd:ee:10"; ip-address = "192.168.20.10"; }
            # { hw-address = "aa:bb:cc:dd:ee:11"; ip-address = "192.168.20.11"; }
          ];
        }
      ];
    };
  };

  # --- Mosquitto (MQTT) -------------------------------------------------------
  #
  # Frigate publishes events here and the Home Assistant Frigate integration
  # discovers cameras over it, so it's needed even in the live-only milestone.
  # Localhost-only, so anonymous access is fine.
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "127.0.0.1";
        port = 1883;
        settings.allow_anonymous = true;
      }
    ];
  };

  # --- Frigate NVR (live only) ------------------------------------------------
  #
  # The module force-enables services.nginx to serve the UI vhost. We move its
  # public listen off the default port 80 to 8971 (see the nginx override below),
  # so it's reachable at http://shire.local:8971 - keeping every server on its own
  # high port. It only auto-enables hardware.coral.usb when an edgetpu detector is
  # configured - we configure none, so no Coral is required for this milestone.
  #
  # NOTE ON RTSP CREDENTIALS: Frigate substitutes env vars with Python .format(),
  # so the reference is {FRIGATE_RTSP_PASSWORD} - BRACES ONLY, no leading '$'. (A
  # '$' is left literal by .format(), producing a wrong "$<password>".) Nix leaves
  # {FRIGATE_RTSP_PASSWORD} untouched (no '$', so no Nix interpolation). Frigate
  # fills it at runtime from the sops-rendered EnvironmentFile set further down,
  # keeping the camera password out of the world-readable Nix store.
  services.frigate = {
    enable = true;
    hostname = "shire.local";
    vaapiDriver = "radeonsi"; # harmless now; ready for hw decode/detection later
    # checkConfig runs at build time without the runtime EnvironmentFile, so give
    # the env var a placeholder value for validation.
    preCheckConfig = "export FRIGATE_RTSP_PASSWORD=placeholder";
    settings = {
      mqtt = {
        enabled = true;
        host = "127.0.0.1";
      };
      # go2rtc restream (copy-through) of the main stream, for smooth live view
      # in the Frigate UI and in Home Assistant.
      go2rtc.streams = {
        barn_stall_1 = [ "rtsp://admin:{FRIGATE_RTSP_PASSWORD}@192.168.20.10:554/cam/realmonitor?channel=1&subtype=0" ];
        barn_stall_2 = [ "rtsp://admin:{FRIGATE_RTSP_PASSWORD}@192.168.20.11:554/cam/realmonitor?channel=1&subtype=0" ];
      };
      cameras = {
        barn_stall_1 = {
          ffmpeg.inputs = [
            {
              path = "rtsp://admin:{FRIGATE_RTSP_PASSWORD}@192.168.20.10:554/cam/realmonitor?channel=1&subtype=1";
              roles = [ "detect" ];
            }
          ];
          detect.enabled = false; # no object detection yet (no Coral required)
          # Live view uses the go2rtc stream of the same name (barn_stall_1) automatically.
        };
        barn_stall_2 = {
          ffmpeg.inputs = [
            {
              path = "rtsp://admin:{FRIGATE_RTSP_PASSWORD}@192.168.20.11:554/cam/realmonitor?channel=1&subtype=1";
              roles = [ "detect" ];
            }
          ];
          detect.enabled = false;
          # Live view uses the go2rtc stream of the same name (barn_stall_2) automatically.
        };
      };
      record.enabled = false; # no recording yet -> no storage concern
    };
  };

  # Camera RTSP password comes from sops (secrets/shire.yaml, key
  # frigate-rtsp-password; backed up in 1Password as "shire frigate camera rtsp").
  # Frigate does a hard ${...} substitution on config.yml at startup, so we hand it
  # the value as FRIGATE_RTSP_PASSWORD via a sops-rendered EnvironmentFile. Set the
  # same password on each camera's admin account when provisioning them. The value
  # never lands in the world-readable Nix store. (Build-time checkConfig has no sops,
  # so it uses the preCheckConfig placeholder above.)
  sops.secrets."frigate-rtsp-password" = {};
  sops.templates."frigate-rtsp.env".content =
    "FRIGATE_RTSP_PASSWORD=${config.sops.placeholder."frigate-rtsp-password"}";
  systemd.services.frigate.serviceConfig.EnvironmentFile =
    config.sops.templates."frigate-rtsp.env".path;

  # Serve the Frigate UI on a high port instead of the module's default 80, to
  # match the "one server per high port" convention. The module sets no explicit
  # public listen on this vhost, so this override doesn't fight it; Frigate's
  # internal 127.0.0.1:5000 listener is injected separately and is untouched.
  services.nginx.virtualHosts."shire.local".listen = [
    { addr = "0.0.0.0"; port = 8971; } # Frigate's conventional authenticated port
  ];

  # --- go2rtc restreamer (smooth live view) -----------------------------------
  # The NixOS frigate module proxies WebRTC/MSE live view to go2rtc on
  # 127.0.0.1:1984 and orders frigate `after go2rtc.service` - but it does NOT
  # run go2rtc, so we must, or live view falls back to a ~0.1fps jsmpeg slideshow.
  # Streams are named after the cameras so Frigate finds them (it queries
  # /api/streams?src=<camera>). NOTE: go2rtc uses ${VAR} env syntax (with the '$',
  # unlike Frigate's {VAR}); the password comes from the same sops-rendered
  # EnvironmentFile. The \${...} below is escaped so Nix emits a literal
  # ${FRIGATE_RTSP_PASSWORD} for go2rtc to substitute at runtime.
  services.go2rtc = {
    enable = true;
    settings = {
      api.listen = "127.0.0.1:1984";
      streams = {
        barn_stall_1 = "rtsp://admin:\${FRIGATE_RTSP_PASSWORD}@192.168.20.10:554/cam/realmonitor?channel=1&subtype=0";
        barn_stall_2 = "rtsp://admin:\${FRIGATE_RTSP_PASSWORD}@192.168.20.11:554/cam/realmonitor?channel=1&subtype=0";
      };
    };
  };
  systemd.services.go2rtc.serviceConfig.EnvironmentFile = config.sops.templates."frigate-rtsp.env".path;

  # --- Home Assistant (stable, from pinned nixos-25.11) -----------------------
  services.home-assistant = {
    enable = true;
    extraComponents = [ "default_config" "mqtt" "mobile_app" "stream" ];
    customComponents = with pkgs.home-assistant-custom-components; [ frigate ];
    config = {
      default_config = {};
      homeassistant = {
        name = "Home";
        unit_system = "us_customary";
        time_zone = "America/New_York";
      };
      http = {};
    };
  };

  # --- Firewall (merges with the list in shire.nix) ---------------------------
  # Frigate UI (8971) and Home Assistant (8123) on the LAN; wg0 is already trusted,
  # so both are reachable over WireGuard without extra rules. Kea DHCP (UDP 67)
  # is opened on the camera interface only.
  networking.firewall.allowedTCPPorts = [ 8971 8123 ];
  networking.firewall.interfaces.enp3s0.allowedUDPPorts = [ 67 ];

  # ---------------------------------------------------------------------------
  #   Deferred (documented, not enabled now):
  #
  #   * Object detection + Coral USB TPU:
  #       settings.detectors.coral = { type = "edgetpu"; device = "usb"; };
  #       set detect.enabled = true (+ detect stream dimensions) per camera and
  #       ffmpeg.hwaccel_args = "preset-vaapi". The module then auto-enables
  #       hardware.coral.usb.
  #   * Recording: record.enabled = true
  #       Need to determine storage strategy.
  #       ~150 GB/day for 2 cameras 24/7 - must not sit on the NVMe root.
  # ---------------------------------------------------------------------------
}

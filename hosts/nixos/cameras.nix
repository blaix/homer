{ pkgs, ... }:
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
  #     - Home Assistant: open http://shire.local:8123 and create the admin
  #       account (onboarding). Then add two integrations from the HA UI:
  #         * MQTT     -> broker 127.0.0.1, port 1883
  #         * Frigate  -> URL http://127.0.0.1:5000
  #       The Frigate integration surfaces each camera as an HA entity.
  #     - HA companion app: install on the phone; on home WiFi it finds shire
  #       (http://shire.local:8123). Remotely, connect WireGuard and use
  #       http://10.100.0.1:8123.
  #     - Camera RTSP password: once the cameras are configured, write it to
  #       /etc/frigate/rtsp.env (see EnvironmentFile note below).
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
  # NOTE ON RTSP CREDENTIALS: the \${FRIGATE_RTSP_PASSWORD} below is escaped so
  # Nix leaves the literal env-var reference in config.yml; Frigate substitutes
  # it at runtime from the EnvironmentFile set further down. This keeps the
  # camera password out of the world-readable Nix store.
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
        barn_stall_1 = [ "rtsp://admin:\${FRIGATE_RTSP_PASSWORD}@192.168.20.10:554/cam/realmonitor?channel=1&subtype=0" ];
        barn_stall_2 = [ "rtsp://admin:\${FRIGATE_RTSP_PASSWORD}@192.168.20.11:554/cam/realmonitor?channel=1&subtype=0" ];
      };
      cameras = {
        barn_stall_1 = {
          ffmpeg.inputs = [
            {
              path = "rtsp://admin:\${FRIGATE_RTSP_PASSWORD}@192.168.20.10:554/cam/realmonitor?channel=1&subtype=1";
              roles = [ "detect" ];
            }
          ];
          detect.enabled = false; # no object detection yet (no Coral required)
          # Live view uses the go2rtc stream of the same name (barn_stall_1) automatically.
        };
        barn_stall_2 = {
          ffmpeg.inputs = [
            {
              path = "rtsp://admin:\${FRIGATE_RTSP_PASSWORD}@192.168.20.11:554/cam/realmonitor?channel=1&subtype=1";
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

  # RTSP password kept out of the Nix store. Optional file (leading '-'), created
  # by hand on shire once the cameras are provisioned:
  #   sudo install -Dm600 /dev/stdin /etc/frigate/rtsp.env <<<'FRIGATE_RTSP_PASSWORD=...'
  systemd.services.frigate.serviceConfig.EnvironmentFile = "-/etc/frigate/rtsp.env";

  # Serve the Frigate UI on a high port instead of the module's default 80, to
  # match the "one server per high port" convention. The module sets no explicit
  # public listen on this vhost, so this override doesn't fight it; Frigate's
  # internal 127.0.0.1:5000 listener is injected separately and is untouched.
  services.nginx.virtualHosts."shire.local".listen = [
    { addr = "0.0.0.0"; port = 8971; } # Frigate's conventional authenticated port
  ];

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
  #   * RTSP secret: optionally move /etc/frigate/rtsp.env into sops-nix once
  #       that's bootstrapped for shire.
  # ---------------------------------------------------------------------------
}

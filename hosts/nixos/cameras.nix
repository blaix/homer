{ config, lib, pkgs, ... }:

let
  # ---------------------------------------------------------------------------
  #   Adding a camera:
  #
  #     1. Plug it into a PoE port
  #     2. run:  provision-camera <ip>
  #     2. Add a line here, then `just switch shire`.
  #
  #   Keep addresses below .100 - see the provisioning note on enp3s0 below.
  # ---------------------------------------------------------------------------
  cameras = {
    barn_stall_1 = "192.168.20.10";
    barn_stall_2 = "192.168.20.11";
  };

  # Amcrest/Dahua RTSP URL. subtype 0 = main stream (2960x1668 here), used for
  # live view; subtype 1 = substream (704x480), used for Frigate's detect role.
  #
  # NOTE ON RTSP CREDENTIALS: Frigate substitutes env vars with Python .format(),
  # so the reference is {FRIGATE_RTSP_PASSWORD} - BRACES ONLY, no leading '$'. (A
  # '$' is left literal by .format(), producing a wrong "$<password>".) Nix leaves
  # {FRIGATE_RTSP_PASSWORD} untouched (no '$', so no Nix interpolation). Frigate
  # fills it at runtime from the sops-rendered EnvironmentFile set further down,
  # keeping the camera password out of the world-readable Nix store.
  rtspFrigate = ip: subtype:
    "rtsp://admin:{FRIGATE_RTSP_PASSWORD}@${ip}:554/cam/realmonitor?channel=1&subtype=${toString subtype}";

  # Same URL for the standalone go2rtc service, which uses ${VAR} env syntax
  # (with the '$', unlike Frigate's {VAR}) and reads the same EnvironmentFile.
  # The \${...} is escaped so Nix emits a literal ${FRIGATE_RTSP_PASSWORD}.
  rtspGo2rtc = ip:
    "rtsp://admin:\${FRIGATE_RTSP_PASSWORD}@${ip}:554/cam/realmonitor?channel=1&subtype=0";
in
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
  #     - Frigate UI: nothing to do. It has no login, because it is reachable
  #       only over WireGuard - see the "VPN-only, no login" note further down.
  #       Connect the VPN and open http://10.100.0.1:8971.
  #     - Home Assistant: open http://shire.local:8123 and create the admin
  #       account (onboarding). Then add two integrations from the HA UI:
  #         * MQTT     -> broker 127.0.0.1, port 1883
  #         * Frigate  -> URL http://127.0.0.1:5000
  #       The Frigate integration surfaces each camera as an HA entity.
  #     - HA companion app: install on the phone; on home WiFi it finds shire
  #       (http://shire.local:8123). Remotely, connect WireGuard and use
  #       http://10.100.0.1:8123.
  #     - Cameras: run `provision-camera <ip>` on shire (see pkgs/provision-camera.nix),
  #       then add a line to the `cameras` attrset at the top of this file. The
  #       script sets the camera's admin password from sops and pins its static
  #       IP over the HTTP CGI API - no camera web UI needed.
  # ---------------------------------------------------------------------------

  # --- Camera subnet on the second NIC (enp3s0 -> Reolink PoE switch) ---------
  #
  # eno1 stays on the LAN (NetworkManager/DHCP, 192.168.7.x). enp3s0 becomes the
  # gateway for a dedicated camera subnet. NetworkManager must leave it alone so
  # the static addresses below stick.
  networking.networkmanager.unmanaged = [ "interface-name:enp3s0" ];
  networking.interfaces.enp3s0.ipv4.addresses = [
    { address = "192.168.20.1"; prefixLength = 24; }
    # Provisioning address. A factory-reset Amcrest/Dahua camera tries DHCP,
    # finds no server on this segment (we deliberately run none - see below),
    # and falls back to a hardcoded 192.168.1.108. This second address is how
    # shire reaches a brand-new camera to configure it; `provision-camera` uses
    # it, and it is why cameras get addresses below .100 - so a camera being
    # provisioned can never collide with one already in service.
    { address = "192.168.1.2"; prefixLength = 24; }
  ];

  # Cameras have no internet path: shire never forwards their traffic. This is
  # already the kernel default; pinned so the isolation can't silently regress.
  # If IP forwarding is ever enabled (e.g. WireGuard -> LAN routing), add an
  # explicit drop for saddr 192.168.20.0/24 in networking.firewall.extraForwardRules.
  boot.kernel.sysctl."net.ipv4.ip_forward" = 0;

  # NO DHCP SERVER ON THIS SEGMENT, on purpose. Cameras get a static address
  # written into their own NVRAM by `provision-camera`. A DHCP server here was
  # tried and removed, for two reasons worth remembering:
  #   * It bought nothing. Provisioning a new camera needs the 192.168.1.108
  #     fallback path regardless, and once a camera is reachable there it is
  #     simpler to just set its address than to discover its MAC, write a
  #     reservation, redeploy, and reboot it.
  #   * These cameras would not take a lease anyway. Kea ACKed every request and
  #     the camera looped on DHCPREQUEST forever, never binding - they appear to
  #     want a `routers` option, which this subnet deliberately does not offer.
  # Running no DHCP server also makes the 192.168.1.108 fallback deterministic
  # rather than a race, which is what makes provisioning repeatable.

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
  # public listen off the default port 80 to the WireGuard address on port 8971
  # (see the nginx override below), so it's reachable at http://10.100.0.1:8971 -
  # keeping every server on its own high port. It only auto-enables
  # hardware.coral.usb when an edgetpu detector is configured - we configure none,
  # so no Coral is required for this milestone.
  services.frigate = {
    enable = true;
    hostname = "shire.local";
    vaapiDriver = "radeonsi"; # harmless now; ready for hw decode/detection later
    # checkConfig runs at build time without the runtime EnvironmentFile, so give
    # the env var a placeholder value for validation.
    preCheckConfig = "export FRIGATE_RTSP_PASSWORD=placeholder";
    settings = {
      # VPN-ONLY, NO LOGIN. The UI is bound to the WireGuard address (nginx
      # override below) and is not in the firewall's LAN port list, so the only
      # way in is over the tunnel - which is already authenticated by WireGuard.
      # A second password in front of that bought nothing, so auth is off and
      # there is no login page.
      #
      # auth.enabled = false alone would leave every request in the "viewer"
      # role (read-only: no Settings, no config editor, no user management),
      # because Frigate's /auth endpoint falls back to proxy.default_role when
      # no user is authenticated - and that defaults to "viewer". Setting it to
      # "admin" is what makes the unauthenticated session a full admin one.
      auth.enabled = false;
      proxy.default_role = "admin";

      mqtt = {
        enabled = true;
        host = "127.0.0.1";
      };
      # go2rtc restream (copy-through) of the main stream, for smooth live view
      # in the Frigate UI and in Home Assistant.
      go2rtc.streams = lib.mapAttrs (_: ip: [ (rtspFrigate ip 0) ]) cameras;
      # Live view uses the go2rtc stream of the same name automatically.
      cameras = lib.mapAttrs (_: ip: {
        ffmpeg.inputs = [
          {
            path = rtspFrigate ip 1;
            roles = [ "detect" ];
          }
        ];
        detect.enabled = false; # no object detection yet (no Coral required)
      }) cameras;
      record.enabled = false; # no recording yet -> no storage concern
    };
  };

  # Camera RTSP password comes from sops (secrets/shire.yaml, key
  # frigate-rtsp-password; backed up in 1Password as "shire frigate camera rtsp").
  # Frigate does a hard ${...} substitution on config.yml at startup, so we hand it
  # the value as FRIGATE_RTSP_PASSWORD via a sops-rendered EnvironmentFile. The same
  # secret is what `provision-camera` writes onto each camera's admin account. The
  # value never lands in the world-readable Nix store. (Build-time checkConfig has
  # no sops, so it uses the preCheckConfig placeholder above.)
  sops.secrets."frigate-rtsp-password" = {};
  sops.templates."frigate-rtsp.env".content =
    "FRIGATE_RTSP_PASSWORD=${config.sops.placeholder."frigate-rtsp-password"}";
  systemd.services.frigate.serviceConfig.EnvironmentFile =
    config.sops.templates."frigate-rtsp.env".path;

  # Serve the Frigate UI on a high port instead of the module's default 80, to
  # match the "one server per high port" convention. The module sets no explicit
  # public listen on this vhost, so this override doesn't fight it; Frigate's
  # internal 127.0.0.1:5000 listener is injected separately and is untouched
  # (Home Assistant's Frigate integration talks to it there).
  #
  # Binding to 10.100.0.1 - shire's WireGuard address - rather than 0.0.0.0 is
  # what makes the UI VPN-only: it is not listening on the LAN at all, so this
  # holds even if the firewall is ever misconfigured. It also means mDNS won't
  # help you (shire.local resolves to the LAN address), so the URL is the bare
  # IP: http://10.100.0.1:8971. This vhost is the only server block on that
  # address:port, so nginx serves it regardless of the Host header.
  services.nginx.virtualHosts."shire.local".listen = [
    { addr = "10.100.0.1"; port = 8971; } # Frigate's conventional UI port
  ];

  # nginx binds a specific address, so wg0 must exist before it starts or the
  # bind fails. (nginx has Restart=always and would eventually recover, but only
  # after up to 10s of downtime per attempt.)
  systemd.services.nginx = {
    after = [ "wireguard-wg0.service" ];
    wants = [ "wireguard-wg0.service" ];
  };

  # --- go2rtc restreamer (smooth live view) -----------------------------------
  # The NixOS frigate module proxies WebRTC/MSE live view to go2rtc on
  # 127.0.0.1:1984 and orders frigate `after go2rtc.service` - but it does NOT
  # run go2rtc, so we must, or live view falls back to a ~0.1fps jsmpeg slideshow.
  # Streams are named after the cameras so Frigate finds them (it queries
  # /api/streams?src=<camera>).
  services.go2rtc = {
    enable = true;
    settings = {
      api.listen = "127.0.0.1:1984";
      streams = lib.mapAttrs (_: ip: rtspGo2rtc ip) cameras;
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
  # Home Assistant (8123) on the LAN. The Frigate UI is deliberately NOT here:
  # it listens only on the WireGuard address (see the nginx override above), and
  # wg0 is a trusted interface in shire.nix, so it needs no port opened - which
  # is exactly what keeps it off the LAN. Nothing needs to be opened on the
  # camera interface either: shire only ever makes outbound connections to the
  # cameras (RTSP and the HTTP CGI API), never accepts inbound from them.
  networking.firewall.allowedTCPPorts = [ 8123 ];

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

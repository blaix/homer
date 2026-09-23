{ config, pkgs, lib, inputs, ... }:
{
  imports = [
    ./blaixapps-base.nix
    ./common.nix
    inputs.dia.nixosModules.dia
    inputs.doitanyway.nixosModules.doitanyway
    inputs.growth.nixosModules.growth
    inputs.blog.nixosModules.blog
    inputs.prettynice-software.nixosModules.prettynice-software
  ];

  # Hostname
  networking.hostName = "blaixapps";

  # Enable doitanyway service
  services.doitanyway = {
    enable = true;
    domain = "dia.blaix.com";
    acmeEmail = "justin@blaix.com";
    enableBackups = true;
  };

  # dia sync server. dia-sync.blaix.com, not dia.blaix.com — that one is
  # doitanyway, the previous iteration this app succeeds.
  #
  # nix does not compile this one: nixpkgs ships Swift 5.10.1 and dia needs 6.2,
  # so the binary is built in a container on a Linux host and published to the
  # private blaix/dia-dist repo, which dia takes as a flake input. That input is
  # fetched during *evaluation* — here, on the Mac — and the source is copied to
  # the build host, so blaixapps needs no credentials for the forge. See the dia
  # README, "How the Linux server binary gets built".
  #
  # The consequence for this host: `nix flake update dia` is what picks up a new
  # server build, and dia's own flake.lock decides which binary that is. If dia
  # has no published binary for x86_64-linux, its package attribute does not
  # exist and this host's rebuild fails rather than deploying nothing.
  #
  # Credentials are not in nix: /etc/htpasswd is a plain file on the host.
  # Add dia's line with (no -c — it would truncate the file):
  #   sudo nix shell nixpkgs#apacheHttpd --command htpasswd -B /etc/htpasswd dia
  services.dia = {
    enable = true;
    domain = "dia-sync.blaix.com";
    acmeEmail = "justin@blaix.com";
    port = 3035;                      # next free: 3030-3034 and 3040 are taken
    basicAuthFile = "/etc/htpasswd";
    enableBackups = true;
  };

  # Enable growth service
  services.growth = {
    enable = true;
    domain = "growth.blaix.com";
    acmeEmail = "justin@blaix.com";
    appPort = 3030;
    ws4sqlPort = 12322;
    basicAuth.enable = true;
  };

  # Enable blog
  services.blog = {
    enable = true;
    domain = "blog.blaix.com";
    acmeEmail = "justin@blaix.com";
  };

  # Enable prettynice.software website
  services.prettynice-software = {
    enable = true;
    domain = "prettynice.software";
    acmeEmail = "justin@blaix.com";
  };

  # Monitoring: Prometheus + Grafana
  # TODO: alerting! (will need an outbound email service. msmtp + fastmail?)

  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    listenAddress = "127.0.0.1";
    enabledCollectors = [ "systemd" ];
  };

  services.prometheus = {
    enable = true;
    port = 9090;
    listenAddress = "127.0.0.1";
    retentionTime = "30d";
    globalConfig.scrape_interval = "15s";
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{ targets = [ "127.0.0.1:9100" ]; }];
      }
    ];
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3034;
        domain = "monitor.blaix.com";
        root_url = "https://monitor.blaix.com";
      };
      security.admin_password = "$__file{/etc/grafana-admin-password}";
      security.secret_key = "$__file{/etc/grafana-secret-key}";
    };
    provision = {
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://127.0.0.1:9090";
          isDefault = true;
          access = "proxy";
        }
      ];
      dashboards.settings.providers = [
        {
          name = "default";
          options.path = "/etc/grafana-dashboards";
        }
      ];
    };
  };

  environment.etc."grafana-dashboards/node-exporter.json".source =
    builtins.fetchurl {
      url = "https://grafana.com/api/dashboards/1860/revisions/43/download";
      sha256 = "1jr2w0lw64781vdl788fl7ir6x6ixkzjcs5cbfll5m77qiv94icq";
    };

  services.nginx.virtualHosts."monitor.blaix.com" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:3034";
      proxyWebsockets = true;
    };
  };
  security.acme.certs."monitor.blaix.com".email = "justin@blaix.com";

  # Forgejo: self-hosted git forge
  services.forgejo = {
    enable = true;
    database.type = "sqlite3";
    lfs.enable = true;
    settings = {
      server = {
        DOMAIN = "git.blaix.com";
        ROOT_URL = "https://git.blaix.com/";
        HTTP_PORT = 3040;
        HTTP_ADDR = "127.0.0.1";
      };
      service.DISABLE_REGISTRATION = true;
    };
    dump = {
      enable = true;
      interval = "daily";
      backupDir = "/var/lib/forgejo/backups";
      age = "30d";
    };
  };

  services.nginx.virtualHosts."git.blaix.com" = {
    enableACME = true;
    forceSSL = true;
    extraConfig = ''
      client_max_body_size 512M;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:3040";
      proxyWebsockets = true;
    };
  };
  security.acme.certs."git.blaix.com".email = "justin@blaix.com";
}

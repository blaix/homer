{ config, pkgs, lib, inputs, ... }:
{
  imports = [
    ./blaixapps-base.nix
    ./common.nix
    inputs.doitanyway.nixosModules.doitanyway
    inputs.growth.nixosModules.growth
    inputs.mycomics.nixosModules.mycomics
    inputs.mynotes.nixosModules.mynotes
    inputs.myrecords.nixosModules.myrecords
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

  # Enable growth service
  services.growth = {
    enable = true;
    domain = "growth.blaix.com";
    acmeEmail = "justin@blaix.com";
    appPort = 3030;
    ws4sqlPort = 12322;
    basicAuth.enable = true;
  };

  # Enable mycomics service
  services.mycomics = {
    enable = true;
    domain = "comics.blaix.com";
    acmeEmail = "justin@blaix.com";
    appPort = 3031;
    ws4sqlPort = 12323;
    basicAuth.enable = true;
  };

  # Enable mynotes service
  services.mynotes = {
    enable = true;
    domain = "notes.blaix.com";
    port_ = 3033;
    ws4sqlPort = 12325;
    enableBackups = true;
    basicAuthFile = "/etc/htpasswd";
  };
  security.acme.certs."notes.blaix.com".email = "justin@blaix.com";

  # Enable myrecords service
  services.myrecords = {
    enable = true;
    domain = "records.blaix.com";
    acmeEmail = "justin@blaix.com";
    appPort = 3032;
    ws4sqlPort = 12324;
    basicAuth.enable = true;
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

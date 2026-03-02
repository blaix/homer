{ config, pkgs, lib, inputs, ... }:
{
  imports = [
    ./blaixapps-base.nix
    ./common.nix
    inputs.doitanyway.nixosModules.doitanyway
    inputs.growth.nixosModules.growth
    inputs.mycomics.nixosModules.mycomics
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
        http_port = 3033;
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
      url = "https://grafana.com/api/dashboards/1860/revisions/latest/download";
      sha256 = "0phjy96kq4kymzggm0r51y8i2s2z2x3p69bd5nx4n10r33mjgn54";
    };

  services.nginx.virtualHosts."monitor.blaix.com" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:3033";
      proxyWebsockets = true;
    };
  };
  security.acme.certs."monitor.blaix.com".email = "justin@blaix.com";
}

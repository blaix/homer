{ config, pkgs, lib, ... }:
let
  # Only blaixapps scrapes node metrics into prometheus. Elsewhere, skip the
  # fill-rate check and rely on the fixed threshold.
  hasPrometheus = config.services.prometheus.enable
    && config.services.prometheus.exporters.node.enable;

  check = pkgs.writeShellApplication {
    name = "health-alerts";
    runtimeInputs = with pkgs; [ coreutils curl gawk jq systemd ];
    text = ''
      url=$(cat "$CREDENTIALS_DIRECTORY/ntfy-url")
      host=$(hostname)
      state=$STATE_DIRECTORY
      now=$(date +%s)

      notify() {
        curl -fsS -H "Title: $host: $1" -H "Tags: warning" -d "$2" "$url" >/dev/null
      }

      # Repeat a still-true alert at most every 6 hours instead of every run.
      due() {
        local f="$state/$1"
        [ ! -e "$f" ] || [ $(( now - $(stat -c %Y "$f") )) -ge 21600 ]
      }
      mark() { touch "$state/$1" || true; }

      # --- disk: fixed threshold -------------------------------------------
      used=$(df --output=pcent / | tail -1 | tr -dc 0-9)
      if [ "$used" -ge 80 ]; then
        if due disk-full; then
          notify "disk $used% full" "$(df -h / | tail -1)" && mark disk-full
        fi
      else
        rm -f "$state/disk-full"
      fi

      ${lib.optionalString hasPrometheus ''
      # --- disk: fill rate -------------------------------------------------
      # Trend over the last day, so a deploy's temporary build output doesn't
      # look like a disk about to fill.
      query='predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[24h], 3*24*3600) < 0'
      predicted=$(curl -fsS --get http://127.0.0.1:${toString config.services.prometheus.port}/api/v1/query \
        --data-urlencode "query=$query" | jq '.data.result | length') || predicted=0
      if [ "$predicted" -gt 0 ]; then
        if due disk-trend; then
          notify "disk fills within 3 days" "At the last day's rate, / runs out of space within 3 days. Currently $used% used." \
            && mark disk-trend
        fi
      else
        rm -f "$state/disk-trend"
      fi
      ''}

      # --- failed systemd units --------------------------------------------
      # Alert when the set of failed units changes to include something new.
      failed=$(systemctl list-units --state=failed --no-legend --plain | awk '{print $1}' | sort)
      previous=$(cat "$state/failed-units" 2>/dev/null || true)
      new=$(comm -23 <(echo "$failed") <(echo "$previous") | sed '/^$/d')
      if [ -n "$new" ]; then
        notify "systemd unit failed" "$new" && { echo "$failed" > "$state/failed-units" || true; }
      else
        echo "$failed" > "$state/failed-units" || true
      fi
    '';
  };
in
{
  # ---------------------------------------------------------------------------
  #   Push notifications (ntfy) for a filling disk or failed systemd units.
  #   The host's sops file must have an `ntfy-url` (https://ntfy.sh/<topic>).
  #   Subscribe to that topic in the ntfy phone app to receive them.
  # ---------------------------------------------------------------------------

  sops.secrets.ntfy-url = {};

  systemd.services.health-alerts = {
    description = "Push alerts for disk space and failed units";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe check;
      LoadCredential = "ntfy-url:${config.sops.secrets.ntfy-url.path}";
      StateDirectory = "health-alerts";
    };
  };

  systemd.timers.health-alerts = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "15min";
    };
  };
}

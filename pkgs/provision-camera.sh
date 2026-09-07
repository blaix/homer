usage() {
  cat <<'EOF'
Usage: provision-camera [options] <target-ip>

Provisions a new Amcrest/Dahua PoE camera for the Frigate stack on shire:
sets its admin password from sops and pins it to a static address, entirely
over the camera's HTTP CGI API. No camera web UI, no DHCP, no reboot dance.

A factory-reset camera tries DHCP, finds no server on the camera subnet, and
falls back to a hardcoded 192.168.1.108 with credentials admin/admin. shire
holds 192.168.1.2 on enp3s0 precisely so it can reach a camera there (see
hosts/nixos/cameras.nix). That is the default --from address.

After this succeeds, add one line to the `cameras` attrset in
hosts/nixos/cameras.nix and run `just switch shire`.

Options:
  --from <ip>           Where the camera is now (default: 192.168.1.108)
  --old-password <pw>   Its current admin password (default: admin)
  --gateway <ip>        Default gateway to set (default: 192.168.20.1)
  --netmask <mask>      Subnet mask to set (default: 255.255.255.0)
  -n, --dry-run         Show what would be done, change nothing
  -h, --help            Show this help

Password:
  Taken from $FRIGATE_RTSP_PASSWORD if set, otherwise decrypted from
  $HOMER_DIR/secrets/shire.yaml (HOMER_DIR defaults to ~/homer). Every camera
  shares this one admin password because Frigate has a single RTSP credential.

Examples:
  provision-camera 192.168.20.12                  # brand-new camera
  provision-camera --from 192.168.20.12 192.168.20.13   # move an existing one
EOF
}

from_ip="192.168.1.108"
old_password="admin"
gateway="192.168.20.1"
netmask="255.255.255.0"
dry_run=""
target_ip=""

while [ $# -gt 0 ]; do
  case "$1" in
    --from) shift; from_ip="${1:-}" ;;
    --old-password) shift; old_password="${1:-}" ;;
    --gateway) shift; gateway="${1:-}" ;;
    --netmask) shift; netmask="${1:-}" ;;
    -n|--dry-run) dry_run="yes" ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) target_ip="$1" ;;
  esac
  shift
done

if [ -z "$target_ip" ]; then
  usage >&2
  exit 2
fi
if ! echo "$target_ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
  echo "Not an IPv4 address: $target_ip" >&2
  exit 2
fi

# Cameras live below .100 so that a camera being provisioned (which briefly
# holds the factory 192.168.1.108) can never collide with one in service.
case "$target_ip" in
  192.168.20.*) ;;
  *) echo "Warning: $target_ip is outside the camera subnet 192.168.20.0/24" >&2 ;;
esac

# --- the shared admin password ------------------------------------------------
password="${FRIGATE_RTSP_PASSWORD:-}"
if [ -z "$password" ]; then
  secrets="${HOMER_DIR:-$HOME/homer}/secrets/shire.yaml"
  if [ ! -f "$secrets" ]; then
    echo "No \$FRIGATE_RTSP_PASSWORD and no secrets file at $secrets" >&2
    echo "Set HOMER_DIR, or export FRIGATE_RTSP_PASSWORD." >&2
    exit 1
  fi
  if ! password=$(sops -d --extract '["frigate-rtsp-password"]' "$secrets" 2>/dev/null); then
    echo "Could not decrypt frigate-rtsp-password from $secrets" >&2
    echo "Is your age key at ~/.config/sops/age/keys.txt?" >&2
    exit 1
  fi
fi
if [ -z "$password" ]; then
  echo "Decrypted password is empty - refusing to set that on a camera." >&2
  exit 1
fi

# --- helpers ------------------------------------------------------------------

# Probe the CGI API. Prints the HTTP status; 200 means these credentials work.
probe() {
  curl --digest -u "admin:$2" -s -m 8 -o /dev/null -w '%{http_code}' \
    "http://$1/cgi-bin/magicBox.cgi?action=getSystemInfo" 2>/dev/null || echo "000"
}

wait_for() {
  local ip="$1" pw="$2" tries=0
  while [ "$tries" -lt 30 ]; do
    if [ "$(probe "$ip" "$pw")" = "200" ]; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 2
  done
  return 1
}

# --- figure out where the camera actually is -----------------------------------

# Already done? Then this is a no-op, so re-running is always safe.
if [ "$(probe "$target_ip" "$password")" = "200" ]; then
  echo "==> $target_ip already answers with the shared password - nothing to do."
  echo "    Add this to the cameras attrset in hosts/nixos/cameras.nix:"
  echo "      <name> = \"$target_ip\";"
  exit 0
fi

echo "==> Looking for the camera on $from_ip"
current_password=""
if [ "$(probe "$from_ip" "$old_password")" = "200" ]; then
  current_password="$old_password"
  echo "    Found it, using the factory password."
elif [ "$(probe "$from_ip" "$password")" = "200" ]; then
  # Password was already set on a previous, partly-finished run.
  current_password="$password"
  echo "    Found it, password is already set - only the address is left."
else
  echo "No camera answering the CGI API on $from_ip." >&2
  echo "  - Is it plugged into a PoE port and finished booting (~60s)?" >&2
  echo "  - Does shire still hold 192.168.1.2 on enp3s0? (ip -br a show enp3s0)" >&2
  echo "  - If it was provisioned before, pass --from <its current ip>" >&2
  echo "    and --old-password if it is not the factory default." >&2
  exit 1
fi

if [ -n "$dry_run" ]; then
  echo "==> (dry-run) would set the admin password from sops"
  echo "==> (dry-run) would set $from_ip -> $target_ip/$netmask gw $gateway, DHCP off"
  exit 0
fi

# --- set the password ----------------------------------------------------------
if [ "$current_password" = "$password" ]; then
  echo "==> Password already set, skipping."
else
  echo "==> Setting the admin password from sops"
  # -G with --data-urlencode so a password containing & % + or spaces survives.
  result=$(curl --digest -u "admin:$current_password" -s -m 10 -G \
    --data-urlencode "action=modifyPassword" \
    --data-urlencode "name=admin" \
    --data-urlencode "pwd=$password" \
    --data-urlencode "pwdOld=$current_password" \
    "http://$from_ip/cgi-bin/userManager.cgi" || true)
  if ! echo "$result" | grep -qi "^OK"; then
    echo "Password change failed: ${result:-<no response>}" >&2
    exit 1
  fi
  echo "    OK"
  # The camera drops existing digest sessions after a password change.
  sleep 3
  if ! wait_for "$from_ip" "$password"; then
    echo "Camera stopped answering on $from_ip after the password change." >&2
    exit 1
  fi
fi

# --- set the static address ----------------------------------------------------
echo "==> Setting $target_ip/$netmask gw $gateway (DHCP off)"
# The camera moves subnets mid-request, so curl usually reports a broken
# connection here even on success. The poll below is the real check.
curl --digest -u "admin:$password" -s -m 10 \
  "http://$from_ip/cgi-bin/configManager.cgi?action=setConfig\
&Network.eth0.DhcpEnable=false\
&Network.eth0.IPAddress=$target_ip\
&Network.eth0.SubnetMask=$netmask\
&Network.eth0.DefaultGateway=$gateway" >/dev/null 2>&1 || true

echo "==> Waiting for it to come up on $target_ip"
if ! wait_for "$target_ip" "$password"; then
  echo "Camera never appeared on $target_ip." >&2
  echo "It may still be on $from_ip - re-run with --old-password to retry." >&2
  exit 1
fi
echo "    OK"

# --- verify it is actually usable by Frigate -----------------------------------
echo "==> Checking RTSP"
rtsp=$(curl --digest -u "admin:$password" -s -m 8 \
  "http://$target_ip/cgi-bin/configManager.cgi?action=getConfig&name=RTSP" || true)
if echo "$rtsp" | grep -qi "RTSP.Enable=true"; then
  echo "    RTSP enabled on port $(echo "$rtsp" | grep -i 'RTSP.Port=' | cut -d= -f2)"
else
  echo "    WARNING: RTSP does not look enabled - Frigate will not get a stream." >&2
fi

encode=$(curl --digest -u "admin:$password" -s -m 8 \
  "http://$target_ip/cgi-bin/configManager.cgi?action=getConfig&name=Encode" || true)
main=$(echo "$encode" | grep -i 'Encode\[0\].MainFormat\[0\].Video.Width=' | cut -d= -f2)
extra=$(echo "$encode" | grep -i 'Encode\[0\].ExtraFormat\[0\].Video.Width=' | cut -d= -f2)
if [ -n "$main" ] && [ -n "$extra" ]; then
  echo "    main stream ${main}px (live view), substream ${extra}px (detect)"
else
  echo "    WARNING: could not confirm both streams exist." >&2
fi

name=$(curl --digest -u "admin:$password" -s -m 8 \
  "http://$target_ip/cgi-bin/magicBox.cgi?action=getSystemInfo" \
  | grep -i '^deviceType=' | cut -d= -f2 | tr -d '\r')

echo
echo "==> Done. ${name:-camera} is on $target_ip."
echo "    Add one line to the cameras attrset in hosts/nixos/cameras.nix:"
echo
echo "      <name> = \"$target_ip\";"
echo
echo "    then: just switch shire"

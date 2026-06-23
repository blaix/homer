{ pkgs, ... }:
{
  imports = [ ./common.nix ];

  networking = {
    computerName = "bilbo";
    hostName = "bilbo";
  };

  # bilbo runs 24/7 as a secondary home server. Keep it awake while on AC
  # power, but let it sleep normally on battery.
  #
  # nix-darwin's power.sleep.* option uses `systemsetup`, which applies to all
  # power sources. `pmset -c` scopes the setting to "connected to charger"
  # only, leaving the battery (-b) defaults untouched.
  system.activationScripts.postActivation.text = ''
    echo "bilbo: disabling idle sleep on AC power..." >&2
    pmset -c sleep 0
  '';
}

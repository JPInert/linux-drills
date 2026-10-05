# Hub on USB. Airplane mode was left ON after an RF-silence test and mobile data was switched off during install:
# the modem is powered down, so the SIM reads NOT_READY (not ABSENT: the card is seated) and there is no service.
# gsm.* props, the telephony registry and rmnet_data0 are DERIVED by the mock from these settings. The wired WAN is
# unplugged (the failover test), so an on-device ping only succeeds once the cellular link is up.
install -d -m 0700 /var/lib/mock-adb
now=$(date +%s)
cat > /var/lib/mock-adb/state.json <<JSON
{
  "hub": {
    "boot_epoch": $((now - 172800)),
    "wan_up": false,
    "settings": {"global": {"airplane_mode_on": "1", "mobile_data": "0"}},
    "radio": {"airplane": true, "sim": "present", "coverage": true}
  }
}
JSON
chmod 0600 /var/lib/mock-adb/state.json
adb --mock noise main 30 1500
adb --mock noise system 5 1500
L() { adb --mock log radio "$@"; }
L 5460 1901 1901 D SST "[SST0] setRadioPower: airplane mode on -> power=false"
L 5459 1901 1901 D RILJ "[3301]> RADIO_POWER off [PHONE0]"
L 5458 1901 1901 D RILJ "[UNSL]< UNSOL_RESPONSE_RADIO_STATE_CHANGED RADIO_OFF [PHONE0]"
L 5458 905 905 I qcrilNrd "RIL: radio state OFF, modem entering low power"
for ago in 4800 3600 2400 1200 60; do
  L $ago 1901 1901 D SST "[SST0] pollStateDone: OUT_OF_SERVICE (radio off)"
  L $ago 1901 1901 D UiccController "Card state PRESENT, app state NOT_READY (radio off)"
  L $ago 905 905 W qcrilNrd "RIL: modem offline, dropping request LAST_DATA_CALL_FAIL_CAUSE"
  L $((ago - 1)) 1901 1901 D DcTracker "[0] trySetupData failed: radio not available"
done
L 3590 1901 1901 E RILJ "[3512]< SETUP_DATA_CALL error: RADIO_NOT_AVAILABLE [PHONE0]"
adb --mock tick

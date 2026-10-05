. /usr/local/lib/drill/lib.sh
ENV=/etc/hub-sync/hub.env
STATE=/run/sensor-hub/state.json

# the hub is a separate device in real life: it must be up and unchanged
want "the sensor hub (simulator) is running" systemctl is-active --quiet sensor-hub-sim
if [ "$(sha256sum /etc/sensor-hub/hub.conf 2>/dev/null | cut -d' ' -f1)" = "$(cat /var/lib/drill/.hub-conf.sha256)" ]; then
  ok "the hub's own credentials are untouched"
else
  bad "the hub's config was changed: the fix belongs on the NVR, not the hub"
fi

want "hub-sync.service is active" systemctl is-active --quiet hub-sync
want "hub-sync.service is enabled for next boot" systemctl is-enabled --quiet hub-sync

# the token file stays a secret: root-owned, nothing for "other"
if [ -f "$ENV" ]; then
  m=$(stat -c %a "$ENV"); o=$(stat -c %U "$ENV"); g=$(stat -c %G "$ENV")
  if [ "$o" = root ] && [ $((8#$m & 8#007)) -eq 0 ] && [ $((8#$m & 8#022)) -eq 0 ]; then
    ok "$ENV is $m $o:$g (not readable by other users)"
  else
    bad "$ENV is $m $o:$g: the hub token in it is readable/writable by too many users"
  fi
else
  bad "$ENV is missing"
fi

# the token must not leak through `systemctl show` (Environment= in a unit/drop-in)
if systemctl show -p Environment hub-sync 2>/dev/null | grep -q HUB_TOKEN; then
  bad "HUB_TOKEN is set via Environment= in the unit: any user can read it with systemctl show"
else
  ok "the token is not exposed through systemctl show"
fi

# the effect: the hub saw a successful authenticated poll from the CURRENT hub-sync process
pid=$(systemctl show -p MainPID --value hub-sync 2>/dev/null); pid=${pid:-0}
started=0
if [ "$pid" -gt 0 ]; then
  age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
  [ -n "$age" ] && started=$(( $(date +%s) - age - 1 ))
fi
fresh() {
  python3 - "$STATE" "$started" <<'PY' 2>/dev/null
import json, sys, time
s = json.load(open(sys.argv[1])); t = s.get("last_ok_hubsync", 0); st = int(sys.argv[2])
sys.exit(0 if st > 0 and t >= st and time.time() - t < 15 else 1)
PY
}
okpoll=0
for _ in 1 2 3 4 5 6 7; do
  fresh && { okpoll=1; break; }
  sleep 1
done
if [ "$okpoll" = 1 ]; then
  ok "the hub accepted a poll from hub-sync (pid $pid) in the last 15 s"
else
  bad "the hub has not accepted any poll from the running hub-sync (pid $pid)"
  last=$(journalctl -u hub-sync -n 1 -o cat --no-pager 2>/dev/null | cut -c1-90)
  [ -n "$last" ] && info "hub-sync's last log line: $last"
fi
finish

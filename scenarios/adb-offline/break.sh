# The hub is up on the site LAN (answers ping, adbd listens on 5555). What is broken is the adb SERVER on this
# laptop: it still holds a stale transport for the hub from before the hub's last reboot, stuck 'offline'.
# State for the mock adb lives in /var/lib/mock-adb (root-owned; the mock re-execs itself via sudo).
install -d -m 0700 /var/lib/mock-adb
# make the hub "exist" on the network so ping / nc behave exactly like the real thing
ip addr add 10.50.0.77/32 dev lo 2>/dev/null || true
setsid nohup nc -lk 10.50.0.77 5555 </dev/null >/dev/null 2>&1 &
cat > /var/lib/mock-adb/state.json <<'JSON'
{
  "server":  {"running": true},
  "usb_devices": [],
  "devices": [{"serial": "10.50.0.77:5555", "transport": "tcp", "state": "offline", "tid": 1}],
  "next_tid": 2,
  "hosts": {"10.50.0.77": {"hub": true, "ports": {"5555": true}, "authorized": true}}
}
JSON
chmod 0600 /var/lib/mock-adb/state.json
adb --mock tick
sleep 1

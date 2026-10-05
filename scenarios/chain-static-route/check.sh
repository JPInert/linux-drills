. /usr/local/lib/drill/lib.sh
want "systemd-networkd is active" systemctl is-active --quiet systemd-networkd
want "systemd-networkd is enabled for next boot" systemctl is-enabled --quiet systemd-networkd
want "sensor-poller.service is active" systemctl is-active --quiet sensor-poller
d=$(ip -4 route show default | head -1)
case $d in "$(cat /var/lib/drill/.default-route 2>/dev/null)") ok "default route unchanged (via the LAN gateway)" ;;
  *) bad "the default route changed: '${d:-none}' (the sensors need their own route, not a new default)" ;; esac
r=$(ip route get 10.60.0.20 2>&1 | head -1)
case $r in *"via 10.60.255.1 dev eth1"*) ok "10.60.0.20 is routed via the sensor router (10.60.255.1 on eth1)" ;;
  *) bad "traffic for the sensor VLAN goes: '${r}'" ;; esac
# persistent: what networkd will apply to eth1 at the next boot (first matching .network file wins,
# plus its .network.d/*.conf drop-ins)
p=$(python3 - <<'PY'
import fnmatch, glob, os, re
dirs = ["/etc/systemd/network", "/run/systemd/network", "/usr/lib/systemd/network", "/lib/systemd/network"]
files = {}
for d in reversed(dirs):                       # /etc overrides same-named files elsewhere
    for f in glob.glob(d + "/*.network"):
        files[os.path.basename(f)] = f
def sections(text):
    cur, out = None, []
    for line in text.splitlines():
        line = line.strip()
        if not line or line[0] in "#;": continue
        m = re.match(r"\[(\w+)\]$", line)
        if m: cur = {"_": m.group(1)}; out.append(cur); continue
        if cur is not None and "=" in line:
            k, _, v = line.partition("="); cur.setdefault(k.strip(), []).append(v.strip())
    return out
first = None
for name in sorted(files):
    secs = sections(open(files[name]).read())
    names = [n for s in secs if s["_"] == "Match" for v in s.get("Name", []) for n in v.split()]
    if not [s for s in secs if s["_"] == "Match"] or any(fnmatch.fnmatch("eth1", n) for n in names):
        first = name; break
if not first:
    print("none"); raise SystemExit
secs = sections(open(files[first]).read())
for d in dirs:
    for f in sorted(glob.glob("%s/%s.d/*.conf" % (d, first))):
        secs += sections(open(f).read())
good = False
for s in secs:
    if s["_"] == "Route" and "10.60.0.0/24" in s.get("Destination", []) and "10.60.255.1" in s.get("Gateway", []):
        good = True
print(("ok " if good else "missing ") + first)
PY
)
case $p in
  ok*) ok "networkd config for eth1 (${p#ok }) has the 10.60.0.0/24 route via 10.60.255.1: survives a reboot" ;;
  none) bad "no networkd .network file matches eth1 any more" ;;
  *) bad "the networkd config networkd uses for eth1 (${p#missing }) has no route for 10.60.0.0/24 via 10.60.255.1: it is gone at the next reboot" ;;
esac
# the effect: what THIS run of the poller (current PID) got from both hubs in the last few seconds
pid=$(systemctl show -p MainPID --value sensor-poller 2>/dev/null); pid=${pid:-0}
seen() { [ "$pid" -gt 0 ] && journalctl -q -o cat _SYSTEMD_UNIT=sensor-poller.service _PID="$pid" --since "-8s" 2>/dev/null | grep -F "$1" | tail -1; }
for _ in 1 2 3 4 5 6; do
  a=$(seen 10.60.0.20); b=$(seen 10.60.0.21)
  case "$a$b" in *OK*OK*) break ;; esac
  sleep 1
done
for l in "$a" "$b"; do
  case $l in *": OK "*) ok "poller: $l" ;; "") bad "the poller (pid $pid) logged nothing for a hub in the last 8 s" ;; *) bad "poller: $l" ;; esac
done
finish

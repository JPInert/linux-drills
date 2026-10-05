. /usr/local/lib/drill/lib.sh
want "systemd-networkd is active" systemctl is-active --quiet systemd-networkd
want "systemd-networkd is enabled for next boot" systemctl is-enabled --quiet systemd-networkd
want "nvr-recorder.service is active" systemctl is-active --quiet nvr-recorder
# live: which interface holds the box's camera-VLAN address, and what is it really
ifc=$(ip -o -4 addr show | grep ' 10.50.50.2/24 ' | head -1 | cut -d' ' -f2)
if [ -z "$ifc" ]; then bad "no interface holds 10.50.50.2/24 (the camera VLAN address)"
else
  d=$(ip -d link show "$ifc" 2>/dev/null)
  if echo "$d" | grep -q "^[0-9]*: $ifc@eth1:" && echo "$d" | grep -q 'vlan protocol 802.1Q id 50 '; then
    ok "10.50.50.2/24 is on $ifc: VLAN 50 on the trunk eth1"
  else bad "10.50.50.2/24 is on $ifc, which is not VLAN id 50 on eth1 ($(echo "$d" | grep -o 'vlan protocol 802.1Q id [0-9]*' || echo 'not a VLAN interface'))"; fi
fi
# persistent: what networkd builds at the next boot
p=$(python3 - <<'PY'
import fnmatch, glob, os, re
dirs = ["/etc/systemd/network", "/run/systemd/network", "/usr/lib/systemd/network", "/lib/systemd/network"]
def files(ext):
    out = {}
    for d in reversed(dirs):
        for f in glob.glob("%s/*.%s" % (d, ext)):
            out[os.path.basename(f)] = f
    return out
def sections(path):
    cur, out = None, []
    texts = [open(path).read()]
    for d in dirs:
        texts += [open(f).read() for f in sorted(glob.glob("%s/%s.d/*.conf" % (d, os.path.basename(path))))]
    for text in texts:
        for line in text.splitlines():
            line = line.strip()
            if not line or line[0] in "#;": continue
            m = re.match(r"\[(\w+)\]$", line)
            if m: cur = {"_": m.group(1)}; out.append(cur); continue
            if cur is not None and "=" in line:
                k, _, v = line.partition("="); cur.setdefault(k.strip(), []).append(v.strip())
    return out
def get(secs, sec, key):
    return [v for s in secs if s["_"] == sec for v in s.get(key, [])]
def network_for(link):
    nets = files("network")
    for n in sorted(nets):
        secs = sections(nets[n])
        names = [x for v in get(secs, "Match", "Name") for x in v.split()]
        if not [s for s in secs if s["_"] == "Match"] or any(fnmatch.fnmatch(link, x) for x in names):
            return n, secs
    return None, []
n, secs = network_for("eth1")
if not n: print("bad no .network file matches eth1"); raise SystemExit
vl = [x for v in get(secs, "Network", "VLAN") for x in v.split()]
nd = files("netdev")
why = "eth1's %s lists no VLAN" % n if not vl else ""
for name in vl:
    for f in sorted(nd):
        ns = sections(nd[f])
        if name in get(ns, "NetDev", "Name") and "vlan" in get(ns, "NetDev", "Kind"):
            ids = get(ns, "VLAN", "Id")
            m, ms = network_for(name)
            addrs = get(ms, "Network", "Address") + get(ms, "Address", "Address")
            if ids[-1:] == ["50"] and "10.50.50.2/24" in addrs:
                print("ok %s (%s, Id=50) + %s" % (name, f, m)); raise SystemExit
            why = "%s: %s has Id=%s, %s has Address=%s" % (name, f, ",".join(ids) or "none", m, ",".join(addrs) or "none")
            break
    else:
        why = why or "no .netdev defines %s" % name
print("bad " + why)
PY
)
case $p in ok*) ok "networkd config builds ${p#ok }: survives a reboot" ;;
  *) bad "at the next boot networkd would build: ${p#bad }" ;; esac
# the effect: what THIS run of the recorder (current PID) got from both cameras
pid=$(systemctl show -p MainPID --value nvr-recorder 2>/dev/null); pid=${pid:-0}
seen() { [ "$pid" -gt 0 ] && journalctl -q -o cat _SYSTEMD_UNIT=nvr-recorder.service _PID="$pid" --since "-12s" 2>/dev/null | grep "^$1:" | tail -1; }
for _ in 1 2 3 4 5 6; do
  a=$(seen camera1); b=$(seen camera2)
  case "$a$b" in *"200 OK"*"200 OK"*) break ;; esac
  sleep 1
done
for l in "$a" "$b"; do
  case $l in *"200 OK"*) ok "recorder: ${l%%/Streaming*}... 200 OK" ;; "") bad "the recorder (pid $pid) logged nothing for a camera in the last 12 s" ;; *) bad "recorder: $l" ;; esac
done
finish

. /usr/local/lib/drill/lib.sh
RULES=/etc/iptables/rules.v4
want "netfilter-persistent.service is active (the security baseline is loaded)" systemctl is-active --quiet netfilter-persistent
want "netfilter-persistent.service is enabled for next boot" systemctl is-enabled --quiet netfilter-persistent
want "nvr-recorder.service is active" systemctl is-active --quiet nvr-recorder
# live: RTSP must get through; the rest of the baseline must still hold (a filtered port times out,
# an unfiltered one is answered by the camera with "refused" at once)
tries=6
if nc -z -w2 10.50.1.31 554 >/dev/null 2>&1; then ok "tcp/554 (RTSP) to camera1 connects"
else bad "tcp/554 (RTSP) to camera1 still does not connect"; tries=1; fi
for p in 21 23; do
  if nc -zv -w1 10.50.1.31 $p 2>&1 | grep -q refused; then
    bad "tcp/$p to the camera VLAN is no longer filtered (the camera answered 'refused'): the security baseline must stay"
  else ok "tcp/$p to the camera VLAN is still filtered (baseline intact)"; fi
done
# persistent: what rules.v4 will do at the next boot, for a packet to camera1
if iptables-restore --test < "$RULES" >/dev/null 2>&1; then ok "$RULES loads cleanly (iptables-restore --test)"
else bad "$RULES is missing or does not load: netfilter-persistent would fail at boot"; fi
v=$(python3 - "$RULES" <<'PY'
import shlex, sys
chains, cur, pol = {}, None, {}
try:
    lines = open(sys.argv[1]).read().splitlines()
except OSError:
    print("554=? 21=? 23=?"); raise SystemExit
for l in lines:
    l = l.strip()
    if l.startswith("*"): cur = l[1:]; continue
    if cur != "filter" or not l or l.startswith("#"): continue
    if l.startswith(":"):
        n, p = l[1:].split()[:2]; chains.setdefault(n, []); pol[n] = p; continue
    t = shlex.split(l)
    if t[0] in ("-A", "-I"):
        r = {"i": None}
        k = 2
        if t[0] == "-I" and len(t) > 2 and t[2].isdigit(): r["i"] = int(t[2]); k = 3
        r["t"] = t[k:]
        lst = chains.setdefault(t[1], [])
        if t[0] == "-A": lst.append(r)
        else: lst.insert((r["i"] or 1) - 1, r)
def opt(t, *names):
    for i, x in enumerate(t):
        if x in names and i + 1 < len(t): return t[i + 1], (i > 0 and t[i - 1] == "!")
    return None, False
def inside(ip, net):
    import ipaddress
    return ipaddress.ip_address(ip) in ipaddress.ip_network(net, strict=False)
def matches(t, proto, dport):
    for names, test in ((("-p", "--protocol"), lambda v: v == proto or v == "all"),
                        (("-d", "--destination"), lambda v: any(inside("10.50.1.31", n) for n in v.split(","))),
                        (("--dport", "--destination-port"), lambda v: v == str(dport) or v == {554: "rtsp", 21: "ftp", 23: "telnet"}[dport]
                             or (":" in v and int(v.split(":")[0] or 0) <= dport <= int(v.split(":")[1] or 65535))),
                        (("--dports",), lambda v: any(x == str(dport) or (":" in x and int(x.split(":")[0]) <= dport <= int(x.split(":")[1])) for x in v.split(","))),
                        (("-o", "--out-interface"), lambda v: v in ("eth0", "eth+", "e+") )):
        v, neg = opt(t, *names)
        if v is not None and test(v) == neg: return False
    for skip in ("-s", "--source", "-i", "--in-interface", "--sport", "--uid-owner", "--ctstate", "--state"):
        v, neg = opt(t, skip)
        if v is not None and skip in ("--ctstate", "--state"):
            if "NEW" not in v.split(",") and not neg: return False
    return True
def run(chain, proto, dport, depth=0):
    for r in chains.get(chain, []):
        t = r["t"]
        if not matches(t, proto, dport): continue
        j, _ = opt(t, "-j", "--jump")
        if j is None: continue
        if j in ("ACCEPT", "DROP", "REJECT"): return j
        if j == "RETURN": return None
        if j in chains and depth < 10:
            v = run(j, proto, dport, depth + 1)
            if v: return v
    return None
out = []
for p in (554, 21, 23):
    out.append("%d=%s" % (p, run("OUTPUT", "tcp", p) or pol.get("OUTPUT", "ACCEPT")))
print(" ".join(out))
PY
)
case " $v " in *" 554=ACCEPT "*) ok "at the next boot $RULES lets RTSP (tcp/554) through to camera1" ;;
  *) bad "at the next boot $RULES still blocks RTSP to camera1 (the live fix would be lost)" ;; esac
case " $v " in *" 21=ACCEPT "*|*" 23=ACCEPT "*) bad "at the next boot $RULES no longer blocks ftp/telnet to the cameras: the security baseline must stay" ;;
  *) ok "at the next boot $RULES still blocks ftp/telnet to the cameras" ;; esac
# the effect: what THIS run of the recorder (current PID) got from camera1 in the last few seconds
pid=$(systemctl show -p MainPID --value nvr-recorder 2>/dev/null); pid=${pid:-0}
last=
for _ in $(seq 1 $tries); do
  last=$([ "$pid" -gt 0 ] && journalctl -q -o cat _SYSTEMD_UNIT=nvr-recorder.service _PID="$pid" --since "-10s" 2>/dev/null | grep '^camera1:' | tail -1)
  case $last in *"200 OK"*) break ;; esac
  sleep 1
done
case $last in *"200 OK"*) ok "recorder: $last" ;; "") bad "the recorder (pid $pid) logged nothing for camera1 in the last 10 s" ;;
  *) bad "recorder: $last" ;; esac
finish

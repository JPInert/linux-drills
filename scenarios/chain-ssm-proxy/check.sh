. /usr/local/lib/drill/lib.sh
U=amazon-ssm-agent
want "$U is enabled (starts at boot)" systemctl is-enabled --quiet $U
want "$U is active" systemctl is-active --quiet $U
want "the site proxy (customer side) is still reachable" \
  bash -c '(exec 3<>/dev/tcp/10.44.0.10/3128) 2>/dev/null'

PID=$(systemctl show -p MainPID --value $U 2>/dev/null)
online=0
for _ in 1 2 3 4 5; do
  read -r spid son sts < /run/.drill-ssm-state 2>/dev/null
  if [ "${spid:-x}" = "$PID" ] && [ "${son:-0}" = 1 ] && [ $(( $(date +%s) - ${sts:-0} )) -lt 30 ]; then
    online=1; break; fi
  sleep 1
done
if [ $online = 1 ]; then
  ok "the running agent (pid $PID) reaches AWS: HealthCheck reporting (Online)"
else
  bad "the running agent (pid ${PID:-none}) still cannot reach AWS (Connection Lost)"
  last=$(grep 'caused by' /var/log/amazon/ssm/amazon-ssm-agent.log 2>/dev/null | tail -1 | sed 's/.*": //')
  [ -n "$last" ] && info "last agent error: $last"
fi

# the proxy must come from unit config that survives a reboot (not /run, not
# `systemctl set-environment`), and match what the live agent uses
eval "$(python3 - "$U" "$PID" <<'PY'
import os, re, shlex, subprocess, sys
u, pid = sys.argv[1], sys.argv[2]
def say(k, v): print("%s=%s" % (k, shlex.quote(str(v))))
live, nop = "", ""
try:
    for e in open("/proc/%s/environ" % pid, "rb").read().split(b"\0"):
        k, _, v = e.decode("utf-8", "replace").partition("=")
        if k in ("https_proxy", "HTTPS_PROXY") and v:
            live = live or v
        if k in ("no_proxy", "NO_PROXY") and "169.254.169.254" in v:
            nop = "1"
except (OSError, ValueError):
    pass
say("LIVE", live)
say("NOPROXY", nop)
cat = subprocess.run(["systemctl", "cat", u], capture_output=True, text=True).stdout
persist, runtime, files = "", "", []
cur, sect = None, ""
def envfile(path):
    path = path.lstrip("-")
    try:
        for ln in open(path):
            ln = ln.strip()
            if ln.startswith("export "):
                ln = ln[7:]
            k, _, v = ln.partition("=")
            if k.strip() in ("https_proxy", "HTTPS_PROXY") and v.strip():
                return v.strip().strip('"').strip("'")
    except OSError:
        pass
    return ""
for ln in cat.splitlines():
    m = re.match(r"^# (/\S+)$", ln)
    if m:
        cur, sect = m.group(1), ""
        files.append(cur)
        continue
    s = ln.strip()
    if s.startswith("["):
        sect = s
        continue
    if sect != "[Service]" or not cur:
        continue
    k, _, v = s.partition("=")
    val = ""
    if k.strip() == "Environment":
        try:
            for w in shlex.split(v):
                kk, _, vv = w.partition("=")
                if kk in ("https_proxy", "HTTPS_PROXY") and vv:
                    val = vv
        except ValueError:
            pass
    elif k.strip() == "EnvironmentFile":
        p = v.strip().lstrip("-")
        val = envfile(p) if not p.startswith("/run/") else ""
        if p.startswith("/run/") and envfile(p):
            runtime = runtime or p
    if val:
        if cur.startswith("/run/"):
            runtime = runtime or cur
        else:
            persist = val
say("PERSIST", persist)
say("RUNTIME", runtime)
mgr = subprocess.run(["systemctl", "show-environment"], capture_output=True, text=True).stdout
say("MGR", "1" if re.search(r"^(https_proxy|HTTPS_PROXY)=", mgr, re.M) else "")
nr = subprocess.run(["systemctl", "show", "-p", "NeedDaemonReload", "--value", u],
                    capture_output=True, text=True).stdout.strip()
say("NEEDRELOAD", nr)
PY
)"

if [ -n "$PERSIST" ]; then
  ok "the unit's own config sets https_proxy ($PERSIST): survives a reboot"
  if [ -n "$LIVE" ] && [ "$LIVE" != "$PERSIST" ]; then
    bad "the running agent uses https_proxy=$LIVE but the unit config says $PERSIST"
  fi
else
  bad "no https_proxy in $U's unit config under /etc: after a reboot it is offline again"
  [ -n "$RUNTIME" ] && info "found it only in $RUNTIME: /run is wiped at boot"
  [ -n "$MGR" ] && info "found it in 'systemctl show-environment': that is lost at boot"
fi
[ "$NEEDRELOAD" = yes ] && bad "unit files changed but systemd was not reloaded (daemon-reload)"
[ -n "$NOPROXY" ] \
  && info "no_proxy includes 169.254.169.254 (good practice)" \
  || info "bonus: add no_proxy=169.254.169.254,localhost,127.0.0.1 so metadata calls skip the proxy"
finish

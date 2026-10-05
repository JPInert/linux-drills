. /usr/local/lib/drill/lib.sh
M=/opt/monitoring
D=$M/grafana/provisioning/datasources
want "docker.service is active" systemctl is-active --quiet docker

eval "$(PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import json, shlex
from importlib.machinery import SourceFileLoader
d = SourceFileLoader("mockdocker", "/usr/local/bin/docker").load_module()
def say(k, v): print("%s=%s" % (k, shlex.quote(str(v))))
try:
    st = d.load_state(); d.reconcile(st)
except Exception as e:
    st = {"containers": {}}
for kind, var in (("grafana", "G"), ("prometheus", "P")):
    run = [c for c in st["containers"].values() if c["kind"] == kind and c["status"] == "running"]
    say("N_" + var, len(run))
    if len(run) == 1:
        c = run[0]; lab = c["labels"] or {}
        say(var + "_PID", c["pid"])
        say(var + "_PROJ", lab.get("com.docker.compose.project", ""))
        say(var + "_CMD", " ".join(c["cmd"]))
PY
)"

[ "${N_P:-0}" = 1 ] && ok "one prometheus container is running" \
  || bad "prometheus is not running (${N_P:-0} containers)"
if curl -s --max-time 3 http://127.0.0.1:9090/-/ready | grep -q Ready; then
  ok "Prometheus answers on its usual port 9090 (the NOC federation pulls from it)"
else
  bad "nothing answers http://127.0.0.1:9090/-/ready: the NOC's central server scrapes :9090"
fi

if [ "${N_G:-0}" = 1 ]; then
  ok "one grafana container is running"
  [ "$G_PROJ" = monitoring ] && ok "grafana is managed by compose (project monitoring)" \
    || bad "grafana was started by hand, not by compose: a reboot or update won't reproduce it"
else
  bad "grafana is not running (${N_G:-0} containers)"
fi

# the running Grafana (not just the file) must query Prometheus successfully
good=0
for _ in 1 2 3 4 5 6; do
  eval "$(python3 -c '
import json, shlex, time
try:
    s = json.load(open("/run/.drill-grafana-state"))
    print("S_PID=%s S_OK=%d S_AGE=%d S_N=%d S_URL=%s S_ERR=%s" % (s["pid"], 1 if s["ok"] else 0,
          int(time.time() - s["ts"]), s["n"], shlex.quote(s["url"]), shlex.quote(s["err"])))
except Exception:
    print("S_PID=")
')"
  if [ -n "$S_PID" ] && [ "$S_PID" = "${G_PID:-x}" ] && [ "$S_OK" = 1 ] && [ "$S_AGE" -lt 30 ]; then
    good=1; break; fi
  sleep 1
done
if [ $good = 1 ]; then
  ok "Grafana's datasource ($S_URL) returns data: the panels have data"
elif [ "${S_N:-1}" = 0 ]; then
  bad "the running Grafana has NO datasource: the dashboards can't show anything"
else
  bad "the running Grafana still can't query its datasource: ${S_ERR:-no query yet}"
fi

# persistent: what Grafana will load on the next start must also work
url=$(grep -h '^[[:space:]]*url:' "$D"/*.yaml "$D"/*.yml 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//; s/["'\'']//g; s/[[:space:]]*#.*//')
if [ -z "$url" ]; then
  bad "no datasource url in $D: after a restart Grafana has no datasource"
elif ! echo "$url" | grep -Eq ':9090(/|$)'; then
  bad "the provisioning file points at $url: Prometheus itself is on :9090 (a stand-in on another port won't survive a reboot)"
elif curl -s --max-time 3 "${url%/}/-/ready" | grep -q Ready; then
  ok "the provisioning file's datasource ($url) reaches Prometheus: survives a reboot"
  [ $good = 1 ] && [ -n "$S_URL" ] && [ "${S_URL%/}" != "${url%/}" ] && \
    bad "the running Grafana uses $S_URL but the file says $url"
else
  bad "the provisioning file still points at $url, which does not answer"
fi
finish

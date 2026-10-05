. /usr/local/lib/drill/lib.sh
F=/opt/vehicle-count/compose.yaml
want "docker.service is active" systemctl is-active --quiet docker

# read the mock engine's state (as the engine sees it: dead PIDs reconciled)
eval "$(PYTHONDONTWRITEBYTECODE=1 python3 - "$F" <<'PY'
import shlex, sys
from importlib.machinery import SourceFileLoader
d = SourceFileLoader("mockdocker", "/usr/local/bin/docker").load_module()
def say(k, v): print("%s=%s" % (k, shlex.quote(str(v))))
st = d.load_state(); d.reconcile(st)
run = [c for c in st["containers"].values() if c["status"] == "running"]
fd = [c for c in run if c["kind"] == "vehiclecount"]
say("N_FD", len(fd))
say("N_RELAY", sum(1 for c in run if c["kind"] == "rtsprelay"))
if len(fd) == 1:
    c = fd[0]; lab = c["labels"] or {}
    say("FD_PID", c["pid"]); say("FD_IMAGE", c["image"]); say("FD_NAME", c["name"])
    say("FD_PROJECT", lab.get("com.docker.compose.project", ""))
    say("FD_SERVICE", lab.get("com.docker.compose.service", ""))
    say("FD_HASH", lab.get("com.docker.compose.config-hash", ""))
    say("FD_LOG", c["log"])
try:
    p = d.Project(sys.argv[1])
    say("FILE_HASH", p.svc_hash("vehicle-count") if "vehicle-count" in p.services else "none")
except d.DErr as e:
    say("FILE_HASH", "error"); say("FILE_ERR", e.msg.splitlines()[0])
PY
)"

case ${N_FD:-0} in
  1) ok "one vehicle-count container is running" ;;
  0) bad "no vehicle-count container is running" ;;
  *) bad "$N_FD vehicle-count containers are running (only one may own the cameras)" ;;
esac
[ "${N_RELAY:-0}" -ge 1 ] && ok "rtsp-relay (the live video path) is still running" \
  || bad "rtsp-relay is not running: live video is down now"

if [ "${N_FD:-0}" = 1 ]; then
  [ "$FD_IMAGE" = registry.local/edge/vehicle-count:2.4.1 ] \
    && ok "vehicle-count is on the vendor's 2.4.1 image" \
    || bad "vehicle-count runs $FD_IMAGE: the ticket said stay on 2.4.1"
  if [ "$FD_PROJECT" = vehicle-count ] && [ "$FD_SERVICE" = vehicle-count ]; then
    ok "the container is managed by compose (project vehicle-count)"
  else
    bad "the running vehicle-count was started by hand, not by compose: the next" \
        "'compose up' or a vendor update will not reproduce it"
  fi
  if [ -z "$FD_PROJECT" ]; then
    :                                   # hand-run: no compose hash to compare
  elif [ "$FILE_HASH" = error ]; then
    bad "$F does not parse: ${FILE_ERR:-?}"
  elif [ -n "$FD_HASH" ] && [ "$FD_HASH" = "$FILE_HASH" ]; then
    ok "the running container matches $F"
  else
    bad "the running container does not match $F (file changed, not applied)"
  fi
  listed() { nvidia-smi 2>/dev/null | grep -Eq "^\|[[:space:]]+[0-9]+[[:space:]]+N/A[[:space:]]+N/A[[:space:]]+${FD_PID}[[:space:]]"; }
  for _ in 1 2 3 4 5; do listed && break; sleep 1; done
  if listed; then
    ok "nvidia-smi lists vehicle-count (pid $FD_PID) on the GPU"
  else
    bad "vehicle-count (pid $FD_PID) is not on the GPU"
    hb=$(grep -a 'stats cams' "$FD_LOG" 2>/dev/null | tail -1 | grep -o 'device=[a-z0-9:]* alert_latency_ms=[0-9]*')
    [ -n "$hb" ] && info "last vehicle-count stats: $hb"
  fi
fi
finish

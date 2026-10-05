. /usr/local/lib/drill/lib.sh
F=/opt/vehicle-count/compose.yaml
want "docker.service is active" systemctl is-active --quiet docker

snap() {
PYTHONDONTWRITEBYTECODE=1 python3 - "$F" <<'PY'
import shlex, sys
from importlib.machinery import SourceFileLoader
d = SourceFileLoader("mockdocker", "/usr/local/bin/docker").load_module()
def say(k, v): print("%s=%s" % (k, shlex.quote(str(v))))
try:
    st = d.load_state(); d.reconcile(st)
except Exception:
    st = {"containers": {}}
cs = list(st["containers"].values())
fd = [c for c in cs if c["kind"] == "vehiclecount25"]
run = [c for c in fd if c["status"] == "running" and d.alive(c["pid"])]
say("N_FD", len(fd)); say("N_RUN", len(run))
say("N_RELAY", sum(1 for c in cs if c["kind"] == "rtsprelayj" and c["status"] == "running"))
c = run[0] if len(run) == 1 else (fd[0] if len(fd) == 1 else None)
if c:
    lab = c["labels"] or {}
    say("FD_STATUS", c["status"]); say("FD_PID", c["pid"]); say("FD_IMAGE", c["image"])
    say("FD_RESTART", c.get("restart") or "no")
    say("FD_PROJECT", lab.get("com.docker.compose.project", ""))
    say("FD_HASH", lab.get("com.docker.compose.config-hash", ""))
try:
    p = d.Project(sys.argv[1])
    say("FILE_HASH", p.svc_hash("vehicle-count") if "vehicle-count" in p.services else "none")
except Exception as e:
    say("FILE_HASH", "error"); say("FILE_ERR", str(getattr(e, "msg", e)).splitlines()[0])
PY
}
eval "$(snap)"
# stable = the same process is still alive a few seconds later (no crash loop)
if [ "${N_RUN:-0}" = 1 ]; then
  p1=$FD_PID; sleep 3; eval "$(snap)"
  [ "${N_RUN:-0}" = 1 ] && [ "$FD_PID" = "$p1" ] || N_RUN=0
fi

case "${N_RUN:-0}" in
  1) ok "vehicle-count is running and stays up (pid $FD_PID)" ;;
  0) if [ "${N_FD:-0}" = 0 ]; then bad "there is no vehicle-count container at all"
     else bad "vehicle-count is not running (${FD_STATUS:-?}): no vehicle counting"; fi ;;
  *) bad "$N_RUN vehicle-count containers are running: only one may own the cameras" ;;
esac
[ "${N_RELAY:-0}" -ge 1 ] && ok "rtsp-relay (the live video path) is still running" \
  || bad "rtsp-relay is not running: live video is down"

if [ -n "${FD_IMAGE:-}" ]; then
  [ "$FD_IMAGE" = registry.local/edge/vehicle-count:2.5.0 ] \
    && ok "vehicle-count is on the new 2.5.0 image" \
    || bad "vehicle-count runs $FD_IMAGE: the ticket said stay on the new release"
  case $FD_RESTART in
    unless-stopped|always) ok "restart policy is $FD_RESTART (comes back after a reboot)" ;;
    *) bad "restart policy is '$FD_RESTART': after a reboot or a crash nobody restarts it" ;;
  esac
  if [ "$FD_PROJECT" != vehicle-count ]; then
    bad "vehicle-count was started by hand, not by compose: the next update won't reproduce it"
  elif [ "$FILE_HASH" = error ]; then
    bad "$F does not parse: ${FILE_ERR:-?}"
  elif [ "$FD_HASH" = "$FILE_HASH" ]; then
    ok "the running container matches $F"
  else
    bad "the running container does not match $F (file changed, not applied with up -d)"
  fi
fi

if [ "${N_RUN:-0}" = 1 ]; then
  read -r what _ model pid mver < /run/.drill-fd-state 2>/dev/null
  if [ "$what" = run ] && [ "$pid" = "$FD_PID" ]; then
    case "$mver" in
      *"8.1"*) ok "it loaded the new model ($model: $mver)" ;;
      *) bad "it runs the OLD model ($model: $mver): the ticket said keep the new one" ;;
    esac
  else
    bad "can't confirm which model the running detector loaded"
  fi
fi
finish

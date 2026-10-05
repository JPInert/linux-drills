. /usr/local/lib/drill/lib.sh
want "docker.service is active" systemctl is-active --quiet docker

eval "$(PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import os, shlex
from importlib.machinery import SourceFileLoader
d = SourceFileLoader("mockdocker", "/usr/local/bin/docker").load_module()
def say(k, v): print("%s=%s" % (k, shlex.quote(str(v))))
try:
    st = d.load_state(); d.reconcile(st)
except Exception:
    st = {"containers": {}}
cat = d.catalogue(st)
def present(ref):
    img = d.IMAGES.get(ref)
    return ref in cat and img is not None and \
        os.path.isfile(os.path.join(d.layer_dir(img), "diff", "layer.tar"))
say("HAS_241", 1 if present("registry.local/edge/vehicle-count:2.4.1") else 0)
say("HAS_240", 1 if present("registry.local/edge/vehicle-count:2.4.0") else 0)
for kind, var in (("vehiclecount25", "FD"), ("rtsprelayj", "RL"), ("eventup", "EU")):
    run = [c for c in st["containers"].values() if c["kind"] == kind and
           c["status"] == "running" and d.alive(c["pid"])]
    say("N_" + var, len(run))
    if run:
        c = run[0]
        say(var + "_IMAGE", c["image"])
        say(var + "_PROJ", (c["labels"] or {}).get("com.docker.compose.project", ""))
        mx, mf = d.log_limits(c)
        say(var + "_MAX", mx); say(var + "_FILES", mf)
        say(var + "_LOGTYPE", (c.get("logcfg") or {}).get("Type", "json-file"))
        try:
            say(var + "_LOGSZ", os.path.getsize(c["log"]))
        except OSError:
            say(var + "_LOGSZ", 0)
v = os.statvfs("/var/lib/docker")
say("FREE_MB", v.f_bavail * v.f_frsize // (1024 * 1024))
PY
)"

[ "${FREE_MB:-0}" -ge 30 ] \
  && ok "/var/lib/docker has ${FREE_MB} MB free (the 25 MB 2.5.0 image fits)" \
  || bad "/var/lib/docker has only ${FREE_MB:-0} MB free: the 25 MB update still can't pull"
[ "${HAS_241:-0}" = 1 ] && ok "the running image vehicle-count:2.4.1 is still here" \
  || bad "vehicle-count:2.4.1 (the image in use) is gone"
[ "${HAS_240:-0}" = 1 ] && ok "the approved rollback image vehicle-count:2.4.0 is still here" \
  || bad "vehicle-count:2.4.0 is gone: the ticket said keep the site's rollback image"
[ "${N_FD:-0}" = 1 ] && ok "vehicle-count is running" || bad "vehicle-count is not running"
[ "${N_RL:-0}" = 1 ] && ok "rtsp-relay is running" || bad "rtsp-relay is not running"
if [ "${N_EU:-0}" = 1 ]; then
  ok "event-uploader is running"
  [ "$EU_PROJ" = edge ] || bad "event-uploader was started by hand, not by compose"
  if [ "${EU_MAX:-0}" -gt 0 ]; then
    tot=$(( EU_MAX * EU_FILES / 1024 / 1024 ))
    if [ "$tot" -le 50 ]; then
      ok "event-uploader's log is capped ($EU_LOGTYPE, $((EU_MAX / 1024 / 1024)) MB x $EU_FILES files)"
    else
      bad "event-uploader's log cap is ${tot} MB in total: bigger than this disk can spare"
    fi
  else
    bad "event-uploader's log has no size limit (docker inspect: LogConfig): it will fill the disk again"
  fi
else
  bad "event-uploader is not running (the vehicle events never reach the cloud)"
fi
for v in FD RL; do
  eval "mx=\${${v}_MAX:-0}"
  [ "$mx" -gt 0 ] || info "bonus: $( [ $v = FD ] && echo vehicle-count || echo rtsp-relay ) has no log limit either (a daemon.json default covers every container)"
done
n0=$(cat /var/lib/drill/.nvr-files 2>/dev/null); n1=$(find /srv/nvr/recordings -type f 2>/dev/null | wc -l)
[ "${n1:-0}" -ge "${n0:-1}" ] && ok "camera recordings untouched ($n1 files)" \
  || bad "recordings were deleted ($n1 of $n0 files left): they were never the problem"
finish

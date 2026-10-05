#!/usr/bin/python3
# drill mock of dockerd: owns /run/docker.sock (root:docker 0660) and answers
# /_ping. Container processes live in their own docker-<id>.scope units.
# It is also the restart manager: a container whose process died on its own is
# restarted per its restart policy (100 ms backoff, doubling, max 1 min), shown
# as "Restarting (N) ..." in docker ps meanwhile. Installed as /usr/bin/dockerd.
# At start it loads /etc/docker/daemon.json (a bad file = the daemon won't start,
# like the real one); log-driver/log-opts apply to containers CREATED after that.
# Every second it rotates json-file logs that have a max-size.
import grp, json, os, signal, socket, sys, threading, time
from importlib.machinery import SourceFileLoader

sys.dont_write_bytecode = True

SOCK = "/run/docker.sock"


def log(level, msg, extra=""):
    print('time="%s" level=%s msg="%s"%s' % (time.strftime("%Y-%m-%dT%H:%M:%S.000000000Z",
                                                            time.gmtime()), level, msg,
                                             (" " + extra) if extra else ""), flush=True)


def bye(*_):
    log("info", "Processing signal 'terminated'")
    try:
        os.remove(SOCK)
    except OSError:
        pass
    log("info", "Daemon shutdown complete")
    sys.exit(0)


signal.signal(signal.SIGTERM, bye)
log("info", "Starting up")
DJ = "/etc/docker/daemon.json"
cfg = {}
try:
    with open(DJ) as f:
        text = f.read()
    cfg = json.loads(text) if text.strip() else {}
    if not isinstance(cfg, dict):
        raise ValueError("json: cannot unmarshal array into Go value of type "
                         "map[string]interface {}")
except FileNotFoundError:
    cfg = {}
except ValueError as e:
    msg = str(e)
    if hasattr(e, "pos"):
        msg = "invalid character %r looking for beginning of object key string" % \
            (text[e.pos:e.pos + 1] or "EOF") if "property name" in str(e) else \
            "invalid character %r after object key:value pair" % (text[e.pos:e.pos + 1] or
                                                                  "EOF")
    print("unable to configure the Docker daemon with file %s: %s" % (DJ, msg),
          file=sys.stderr, flush=True)
    sys.exit(1)
_known = {"runtimes", "default-runtime", "log-driver", "log-opts", "data-root",
          "live-restore", "storage-driver", "exec-opts", "registry-mirrors",
          "insecure-registries", "dns", "bip", "default-address-pools", "features",
          "max-concurrent-downloads", "log-level", "iptables", "userland-proxy"}
bad = [k for k in cfg if k not in _known]
if bad:
    print("unable to configure the Docker daemon with file %s: the following directives "
          "don't match any configuration option: %s" % (DJ, ", ".join(bad)),
          file=sys.stderr, flush=True)
    sys.exit(1)
lo = cfg.get("log-opts") or {}
if not isinstance(lo, dict) or any(not isinstance(v, str) for v in lo.values()):
    print("unable to configure the Docker daemon with file %s: json: cannot unmarshal "
          "number into Go struct field Config.log-opts of type string" % DJ,
          file=sys.stderr, flush=True)
    sys.exit(1)
if cfg.get("log-driver", "json-file") not in ("json-file", "local", "journald", "none",
                                              "syslog"):
    print('failed to start daemon: error initializing graphdriver: logger: no log driver '
          'named \'%s\' is registered' % cfg["log-driver"], file=sys.stderr, flush=True)
    sys.exit(1)
import re as _re
for k in ("max-size",):
    if k in lo and not _re.fullmatch(r"\s*[0-9.]+\s*[kKmMgG]?[bB]?\s*", lo[k]):
        print("failed to start daemon: invalid size: '%s'" % lo[k], file=sys.stderr,
              flush=True)
        sys.exit(1)
if "max-file" in lo and not lo["max-file"].isdigit():
    print('failed to start daemon: strconv.Atoi: parsing "%s": invalid syntax' % lo["max-file"],
          file=sys.stderr, flush=True)
    sys.exit(1)
os.makedirs("/run/docker", exist_ok=True)
with open("/run/docker/mock-daemon.json", "w") as f:
    json.dump({"log-driver": cfg.get("log-driver") or "json-file", "log-opts": lo,
               "started": time.time()}, f)
log("info", "Loading containers: start.")
log("info", "Loading containers: done.")
log("info", "Docker daemon", "commit=41ca978 containerd-snapshotter=false "
    "storage-driver=overlay2 version=27.3.1")
log("info", "Daemon has completed initialization")
try:
    os.remove(SOCK)
except OSError:
    pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(SOCK)
os.chown(SOCK, 0, grp.getgrnam("docker").gr_gid)
os.chmod(SOCK, 0o660)
s.listen(16)
log("info", "API listen on %s" % SOCK)


_last_full = [0.0]


def full_warn(st):
    """like dockerd: a log line per container whose log write failed (disk full)"""
    now = time.time()
    if now - _last_full[0] < 30:
        return
    try:
        v = os.statvfs("/var/lib/docker")
    except OSError:
        return
    if v.f_bavail * v.f_frsize > 256 * 1024:
        return
    _last_full[0] = now
    for c in st["containers"].values():
        if c["status"] == "running":
            log("error", "Error writing log message", 'container=%s driver=json-file '
                'error="write %s: no space left on device"' % (c["id"], c["log"]))


def restart_manager():
    d = SourceFileLoader("mockdocker", "/usr/local/bin/docker").load_module()
    while True:
        time.sleep(1)
        try:
            while True:                     # reap the containers this daemon restarted
                pid, _ = os.waitpid(-1, os.WNOHANG)
                if pid == 0:
                    break
        except ChildProcessError:
            pass
        try:
            st = d.load_state()
            d.rotate_logs(st)
            full_warn(st)
            cs = st["containers"].values()
            if not any(c["status"] == "restarting" or c.get("died") or
                       (c["status"] == "running" and not d.alive(c["pid"])) for c in cs):
                continue
            with d.locked():
                st = d.load_state()
                before = {c["id"]: c["status"] for c in st["containers"].values()}
                if d.supervise(st):
                    d.save_state(st)
                for c in st["containers"].values():
                    if before.get(c["id"]) != "restarting" and c["status"] == "restarting":
                        log("info", "shim disconnected", "id=%s namespace=moby" % c["id"])
        except Exception as e:              # never let the daemon die on a bad state file
            log("warning", "restart manager: %s" % e)


threading.Thread(target=restart_manager, daemon=True).start()
while True:
    c, _ = s.accept()
    try:
        c.settimeout(2)
        c.recv(4096)
        c.sendall(b"HTTP/1.1 200 OK\r\nApi-Version: 1.47\r\nContent-Type: text/plain; "
                  b"charset=utf-8\r\nDocker-Experimental: false\r\nOstype: linux\r\n"
                  b"Server: Docker/27.3.1 (linux)\r\nContent-Length: 2\r\n\r\nOK")
    except OSError:
        pass
    finally:
        c.close()

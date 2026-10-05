# shared bits for the monitoring-stack workloads (copied into each kind's
# package dir by break.sh as mdcommon.py). Logs go to the container's json-file log.
import json, os, time

LOG = os.environ.get("MOCKD_LOG", "/dev/null")


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%09dZ" % int((t % 1) * 1e9)


def write(line, t=None, stream="stdout"):
    t = time.time() if t is None else t
    try:
        with open(LOG, "a") as f:
            f.write(json.dumps({"log": line + "\n", "stream": stream, "time": iso(t)}) + "\n")
    except OSError:
        pass


def write_many(recs):
    """[(line, t, stream)] in one open: fast history backfill"""
    try:
        with open(LOG, "a") as f:
            for line, t, stream in recs:
                t = time.time() if t is None else t
                f.write(json.dumps({"log": line + "\n", "stream": stream,
                                    "time": iso(t)}) + "\n")
    except OSError:
        pass


def binds():
    """[(host, container, mode)] for this container (the engine passes them in)"""
    try:
        items = json.loads(os.environ.get("MOCKD_BINDS") or "[]")
    except ValueError:
        items = []
    res = []
    for b in items:
        p = str(b).split(":")
        res.append((p[0], p[1] if len(p) > 1 else p[0], p[2] if len(p) > 2 else "rw"))
    return res


def host_path(cpath):
    """map a path inside the container to the host path behind its bind mount"""
    best = None
    for h, c, _ in binds():
        c = c.rstrip("/") or "/"
        if cpath == c or cpath.startswith(c + "/"):
            if best is None or len(c) > len(best[1]):
                best = (h, c)
    if not best:
        return None
    return best[0].rstrip("/") + cpath[len(best[1]):]


def argval(name, default=None):
    """--name=value or --name value from argv"""
    import sys
    a = sys.argv[1:]
    try:
        a = a or json.loads(os.environ.get("MOCKD_CMD") or "[]")
    except ValueError:
        pass
    for i, x in enumerate(a):
        if x.startswith(name + "="):
            return x.split("=", 1)[1]
        if x == name and i + 1 < len(a):
            return a[i + 1]
    return default


def procname(name):
    """set the process name ss -p / top show (like the real binary's)"""
    try:
        import ctypes
        ctypes.CDLL(None).prctl(15, name.encode()[:15], 0, 0, 0)
    except Exception:
        pass

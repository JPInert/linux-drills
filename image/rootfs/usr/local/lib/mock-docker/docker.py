#!/usr/bin/python3
# drill mock of the docker CLI (27.x) + compose plugin (v2.29): no real engine.
# Containers are real processes (one systemd scope each, like runc's
# docker-<id>.scope); the rest of the engine is a JSON state file.
# Installed by /usr/local/lib/drill/docker-install as /usr/local/bin/docker.
# Images: the built-in IMAGES below + /etc/mock-docker/images.d/*.json.
# A long-running image's process is `python3 -m <kind>` from
# /usr/local/lib/mock-docker/<kind>/__main__.py (no such dir = one-shot image).
# Disk: an image with a "disk" size really occupies that many bytes under
# /var/lib/docker/overlay2 once pulled; rmi/prune delete them. json-file logs
# honour max-size/max-file (daemon.json log-opts at create, compose logging:,
# run --log-opt); dockerd rotates them. `pull` writes bytes and can hit ENOSPC.
import calendar, fcntl, glob, hashlib, json, os, re, shlex, signal, subprocess, sys, time

VERSION, API, COMPOSE_V = "27.3.1", "1.47", "v2.29.7"
SOCK = "/var/run/docker.sock"
ROOT = "/var/lib/docker"
STATE = ROOT + "/mock-state.json"
LOCK = ROOT + "/.mock.lock"
WORKLIB = "/usr/local/lib/mock-docker"
GPU_DIR = "/run/mock-gpu"
HOST = os.uname().nodename
CUDA_IMG = "nvidia/cuda:12.2.0-base-ubuntu22.04"

IMAGES = {
    "registry.local/edge/vehicle-count:2.4.1": dict(
        id="3c9e1f0a7b21d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d",
        age=2 * 86400, size="6.21GB", kind="vehiclecount", workdir="/app",
        cmd=["python3", "-m", "vehiclecount", "--config", "/app/config.yaml"],
        env=["PATH=/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:"
             "/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
             "NVIDIA_VISIBLE_DEVICES=all",
             "NVIDIA_DRIVER_CAPABILITIES=compute,utility",
             "CUDA_VERSION=12.2.0", "FD_VERSION=2.4.1"]),
    "registry.local/edge/vehicle-count:2.3.8": dict(
        id="9a4d2b7c1e0f3a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b",
        age=41 * 86400, size="6.18GB", kind="vehiclecount", workdir="/app",
        cmd=["python3", "-m", "vehiclecount", "--config", "/app/config.yaml"],
        env=["PATH=/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:"
             "/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
             "NVIDIA_VISIBLE_DEVICES=all",
             "NVIDIA_DRIVER_CAPABILITIES=compute,utility",
             "CUDA_VERSION=12.2.0", "FD_VERSION=2.3.8"]),
    "registry.local/edge/rtsp-relay:1.9.2": dict(
        id="5e7f1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7",
        age=64 * 86400, size="48.3MB", kind="rtsprelay", workdir="/",
        cmd=["/mediamtx", "/config/mediamtx.yml"],
        env=["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"]),
    CUDA_IMG: dict(
        id="1d7b3c9e5f2a4b6c8d0e1f2a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e",
        age=380 * 86400, size="239MB", kind="cuda", workdir="/",
        cmd=["/bin/bash"],
        env=["PATH=/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:"
             "/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
             "NVIDIA_VISIBLE_DEVICES=all",
             "NVIDIA_DRIVER_CAPABILITIES=compute,utility",
             "CUDA_VERSION=12.2.0"]),
}
IMAGES_D = "/etc/mock-docker/images.d"
DEF_PATH = "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"


def _load_images_d():
    """extra images: each file is {"repo:tag": {id, age, size, kind, workdir, cmd, env,
    disk, remote, dangling}} ("repo:tag": null removes a built-in image)
    (or a list of such objects with a "ref" key). Missing fields get defaults."""
    for fn in sorted(glob.glob(os.path.join(IMAGES_D, "*.json"))):
        try:
            with open(fn) as f:
                data = json.load(f)
        except (OSError, ValueError):
            continue
        if isinstance(data, list):
            data = {d.get("ref"): d for d in data if isinstance(d, dict) and d.get("ref")}
        if not isinstance(data, dict):
            continue
        for ref, d in data.items():
            if ":" not in ref.split("/")[-1]:
                ref += ":latest"
            if d is None:                        # "ref": null = not on this box
                IMAGES.pop(ref, None)
                continue
            if not isinstance(d, dict):
                continue
            kind = str(d.get("kind") or "none")
            IMAGES[ref] = dict(
                id=str(d.get("id") or hashlib.sha256(ref.encode()).hexdigest()),
                age=int(d.get("age", 30 * 86400)),
                size=str(d.get("size") or d.get("disk") or "120MB"),
                kind=kind, workdir=str(d.get("workdir", "/")),
                cmd=list(d.get("cmd") or ["python3", "-m", kind]),
                env=list(d.get("env") or [DEF_PATH]),
                disk=str(d["disk"]) if d.get("disk") else "",     # real bytes on disk
                remote=bool(d.get("remote")),     # only in the registry until pulled
                dangling=bool(d.get("dangling")))  # <none>:<none> (key it "sha256:<id>")


_load_images_d()


def has_workload(kind):
    return os.path.isfile(os.path.join(WORKLIB, kind, "__main__.py"))


def _size_bytes(s):
    m = re.fullmatch(r"([0-9.]+)\s*([kKMGT]?B)", str(s).strip())
    if not m:
        return 0
    return int(float(m.group(1)) * {"B": 1, "kB": 1e3, "KB": 1e3, "MB": 1e6, "GB": 1e9,
                                     "TB": 1e12}[m.group(2)])


def _hsize(n):
    """docker's units.HumanSize: decimal, 4 significant digits"""
    for u in ("B", "kB", "MB", "GB", "TB"):
        if n < 1000 or u == "TB":
            return ("%.4g%s" % (n, u)) if u != "B" else "%dB" % n
        n /= 1000.0


def catalogue(st=None):
    """IMAGES minus the ones removed with rmi / image prune (kept in the state file)"""
    if st is None:
        try:
            st = load_state()
        except DErr:
            st = {}
    gone = set(st.get("removed_images") or [])
    pulled = set(st.get("pulled_images") or [])
    return {k: v for k, v in IMAGES.items() if k not in gone and
            (not v.get("remote") or k in pulled)}


def img_bytes(img):
    return _size_bytes(img.get("disk") or img["size"])


def layer_dir(img):
    return os.path.join(ROOT, "overlay2", hashlib.sha256(("layer/" + img["id"]).encode())
                        .hexdigest())


def materialise(img):
    """write the image's layer bytes (if it has a "disk" size). ENOSPC -> DErr"""
    n = _size_bytes(img.get("disk") or "0B")
    d = os.path.join(layer_dir(img), "diff")
    f = os.path.join(d, "layer.tar")
    if not n or (os.path.isfile(f) and os.path.getsize(f) >= n):
        return
    os.makedirs(d, exist_ok=True)
    chunk = b"\0" * (1 << 20)
    try:
        with open(f, "wb") as fh:
            left = n
            while left > 0:
                fh.write(chunk[:min(left, len(chunk))])
                left -= len(chunk)
            fh.flush()
            os.fsync(fh.fileno())
    except OSError as e:
        import errno as _e, shutil
        shutil.rmtree(layer_dir(img), ignore_errors=True)
        if e.errno == _e.ENOSPC:
            raise DErr("failed to register layer: write %s/usr/lib/x86_64-linux-gnu/"
                       "libcudnn_ops.so.8.9.7: no space left on device" % d)
        raise DErr("failed to register layer: %s" % e)


def pullable(ref):
    return ref in IMAGES


def pull_image(st, ref, say=None):
    """docker pull: -> True if something was downloaded"""
    img = IMAGES[ref]
    local = ref in catalogue(st)
    f = os.path.join(layer_dir(img), "diff", "layer.tar")
    if local and (not img.get("disk") or os.path.isfile(f)):
        return False
    materialise(img)
    if ref in (st.get("removed_images") or []):
        st["removed_images"].remove(ref)
    st.setdefault("pulled_images", [])
    if ref not in st["pulled_images"]:
        st["pulled_images"].append(ref)
    return True


def daemon_logcfg():
    """the log config dockerd loaded at start (daemon.json log-driver/log-opts)"""
    try:
        with open("/run/docker/mock-daemon.json") as f:
            d = json.load(f)
    except (OSError, ValueError):
        d = {}
    return {"Type": d.get("log-driver") or "json-file",
            "Config": {k: str(v) for k, v in (d.get("log-opts") or {}).items()}}


def parse_size(v):
    """docker's units.RAMInBytes for log max-size: 10m, 512k, 1g, 100 -> bytes"""
    m = re.fullmatch(r"\s*([0-9.]+)\s*([kKmMgG]?)[bB]?\s*", str(v))
    if not m:
        raise ValueError("invalid size: '%s'" % v)
    return int(float(m.group(1)) * {"": 1, "k": 1024, "m": 1024 ** 2, "g": 1024 ** 3}[
        m.group(2).lower()])


def log_limits(c):
    """(max_bytes or 0, max_files) for a container's json-file/local log"""
    lc = c.get("logcfg") or {"Type": "json-file", "Config": {}}
    cf = lc.get("Config") or {}
    if lc.get("Type") == "local":
        mx, mf = cf.get("max-size", "20m"), cf.get("max-file", "5")
    elif lc.get("Type") == "json-file":
        mx, mf = cf.get("max-size"), cf.get("max-file", "1")
    else:
        return 0, 1
    try:
        return (parse_size(mx) if mx else 0), max(1, int(mf))
    except ValueError:
        return 0, 1


def rotate_logs(st):
    """dockerd's json-file rotation: copy+truncate so the writer keeps its file"""
    for c in st["containers"].values():
        mx, mf = log_limits(c)
        if not mx:
            continue
        lg = c["log"]
        try:
            if os.path.getsize(lg) <= mx:
                continue
        except OSError:
            continue
        try:
            import shutil
            for i in range(mf - 1, 1, -1):          # .1 -> .2 ... (oldest falls off)
                if os.path.exists("%s.%d" % (lg, i - 1)):
                    os.replace("%s.%d" % (lg, i - 1), "%s.%d" % (lg, i))
            if mf > 1:
                shutil.copyfile(lg, "%s.1" % lg)
            os.truncate(lg, 0)
        except OSError:
            try:
                os.truncate(lg, 0)
            except OSError:
                pass


NV_CAPS = {"gpu", "nvidia", "compute", "utility", "video", "graphics",
           "display", "compat32"}


class DErr(Exception):
    """message to stderr + exit code, like the CLI prints it"""
    def __init__(self, msg, code=1):
        super().__init__(msg)
        self.msg, self.code = msg, code


def out(s=""):
    sys.stdout.write(s + "\n")


# ------------------------------------------------------------------ YAML
class YErr(Exception):
    pass


def _strip_comment(s):
    q = None
    for i, ch in enumerate(s):
        if q:
            if ch == q:
                q = None
        elif ch in "'\"" and (i == 0 or s[i - 1] in " \t:[{,-"):
            q = ch
        elif ch == "#" and (i == 0 or s[i - 1] in " \t"):
            return s[:i].rstrip()
    return s.rstrip()


def _split_key(t):
    """'key: rest' -> (key, rest) or None"""
    q = None
    if t[:1] in "[{":
        return None
    for i, ch in enumerate(t):
        if q:
            if ch == q:
                q = None
            continue
        if ch in "'\"" and i == 0:
            q = ch
            continue
        if ch == ":" and (i + 1 == len(t) or t[i + 1] in " \t"):
            k = t[:i].strip()
            if len(k) >= 2 and k[0] == k[-1] and k[0] in "'\"":
                k = k[1:-1]
            return k, t[i + 1:].strip()
    return None


def _flow(s, ln):
    s = s.strip()
    pos = [0]

    def ws():
        while pos[0] < len(s) and s[pos[0]] in " \t":
            pos[0] += 1

    def val():
        ws()
        if pos[0] >= len(s):
            raise YErr("yaml: line %d: did not find expected node content" % ln)
        c = s[pos[0]]
        if c == "[":
            pos[0] += 1
            r = []
            ws()
            if s[pos[0]:pos[0] + 1] == "]":
                pos[0] += 1
                return r
            while True:
                r.append(val())
                ws()
                c = s[pos[0]:pos[0] + 1]
                pos[0] += 1
                if c == "]":
                    return r
                if c != ",":
                    raise YErr("yaml: line %d: did not find expected ',' or ']'" % ln)
        if c == "{":
            pos[0] += 1
            r = {}
            ws()
            if s[pos[0]:pos[0] + 1] == "}":
                pos[0] += 1
                return r
            while True:
                k = val()
                ws()
                if s[pos[0]:pos[0] + 1] != ":":
                    raise YErr("yaml: line %d: did not find expected ',' or '}'" % ln)
                pos[0] += 1
                r[str(k)] = val()
                ws()
                c = s[pos[0]:pos[0] + 1]
                pos[0] += 1
                if c == "}":
                    return r
                if c != ",":
                    raise YErr("yaml: line %d: did not find expected ',' or '}'" % ln)
        if c in "'\"":
            e = s.find(c, pos[0] + 1)
            if e < 0:
                raise YErr("yaml: line %d: found unexpected end of stream" % ln)
            v = s[pos[0] + 1:e]
            pos[0] = e + 1
            return v
        st = pos[0]
        while pos[0] < len(s) and s[pos[0]] not in ",]}" and not (
                s[pos[0]] == ":" and pos[0] + 1 < len(s) and s[pos[0] + 1] == " "):
            pos[0] += 1
        return _scalar(s[st:pos[0]].strip(), ln)

    v = val()
    ws()
    if pos[0] != len(s):
        raise YErr("yaml: line %d: did not find expected <document start>" % ln)
    return v


def _scalar(s, ln):
    if s == "":
        return None
    if s[0] in "[{":
        return _flow(s, ln)
    if s[0] in "'\"":
        if len(s) < 2 or s[-1] != s[0]:
            raise YErr("yaml: line %d: found unexpected end of stream" % ln)
        return s[1:-1].replace("''", "'") if s[0] == "'" else \
            s[1:-1].replace('\\"', '"').replace("\\\\", "\\")
    if s in ("null", "Null", "NULL", "~"):
        return None
    if s in ("true", "True", "TRUE"):
        return True
    if s in ("false", "False", "FALSE"):
        return False
    if re.fullmatch(r"[-+]?[0-9]+", s):
        return int(s)
    if re.fullmatch(r"[-+]?([0-9]*\.[0-9]+|[0-9]+\.[0-9]*)([eE][-+]?[0-9]+)?", s):
        return float(s)
    return s


def yaml_load(text):
    L = []
    for n, raw in enumerate(text.split("\n"), 1):
        body = raw.lstrip(" ")
        lead = raw[:len(raw) - len(raw.lstrip(" \t"))]
        if "\t" in lead and raw.strip():
            raise YErr("yaml: line %d: found character that cannot start any token" % n)
        body = raw.lstrip(" \t") if "\t" not in lead else body
        t = _strip_comment(body)
        if not t or t in ("---",):
            continue
        L.append([n, len(raw) - len(body), t])
    if not L:
        return None
    pos = [0]

    def is_seq(t):
        return t == "-" or t.startswith("- ")

    def block(ind):
        return seq(ind, False) if is_seq(L[pos[0]][2]) else mapping(ind)

    def mapping(ind):
        r, seen = {}, {}
        while pos[0] < len(L):
            ln, ci, t = L[pos[0]]
            if ci < ind:
                break
            if ci > ind:
                raise YErr("yaml: line %d: did not find expected key" % ln)
            if is_seq(t):
                raise YErr("yaml: line %d: did not find expected key" % ln)
            kv = _split_key(t)
            if kv is None:
                raise YErr("yaml: line %d: could not find expected ':'" % ln)
            k, rest = kv
            if k in seen:
                raise YErr('yaml: unmarshal errors:\n  line %d: mapping key "%s" '
                           'already defined at line %d' % (ln, k, seen[k]))
            seen[k] = ln
            pos[0] += 1
            nxt = L[pos[0]] if pos[0] < len(L) else None
            if rest == "":
                if nxt and nxt[1] > ind:
                    r[k] = block(nxt[1])
                elif nxt and nxt[1] == ind and is_seq(nxt[2]):
                    r[k] = seq(ind, True)
                else:
                    r[k] = None
            elif rest in ("|", ">", "|-", ">-"):
                lines = []
                while pos[0] < len(L) and L[pos[0]][1] > ind:
                    lines.append(L[pos[0]][2])
                    pos[0] += 1
                r[k] = ("\n" if rest[0] == "|" else " ").join(lines)
            else:
                r[k] = _scalar(rest, ln)
                if nxt and nxt[1] > ind:
                    if _split_key(nxt[2]) or is_seq(nxt[2]):
                        raise YErr("yaml: line %d: mapping values are not allowed "
                                   "in this context" % nxt[0])
                    raise YErr("yaml: line %d: did not find expected key" % nxt[0])
        return r

    def seq(ind, same_as_parent):
        r = []
        while pos[0] < len(L):
            ln, ci, t = L[pos[0]]
            if ci < ind:
                break
            if ci > ind:
                raise YErr("yaml: line %d: did not find expected '-' indicator" % ln)
            if not is_seq(t):
                if same_as_parent:
                    break
                raise YErr("yaml: line %d: did not find expected '-' indicator" % ln)
            rest = t[1:].lstrip(" ")
            if rest == "":
                pos[0] += 1
                nxt = L[pos[0]] if pos[0] < len(L) else None
                r.append(block(nxt[1]) if nxt and nxt[1] > ind else None)
            elif _split_key(rest) is not None and rest[0] not in "'\"":
                L[pos[0]] = [ln, ci + len(t) - len(rest), rest]
                r.append(mapping(L[pos[0]][1]))
            else:
                pos[0] += 1
                r.append(_scalar(rest, ln))
        return r

    first = L[0]
    v = block(first[1])
    if pos[0] < len(L):
        raise YErr("yaml: line %d: did not find expected <document start>" % L[pos[0]][0])
    return v


def yaml_dump(v, ind=0):
    pad = " " * ind
    lines = []
    if isinstance(v, dict):
        for k, x in v.items():
            if isinstance(x, (dict, list)) and x:
                lines.append("%s%s:" % (pad, k))
                lines.append(yaml_dump(x, ind + 2 if isinstance(x, dict) else ind + 2))
            else:
                lines.append("%s%s: %s" % (pad, k, _yscalar(x)))
    elif isinstance(v, list):
        for x in v:
            if isinstance(x, dict) and x:
                sub = yaml_dump(x, ind + 2).split("\n")
                sub[0] = pad + "- " + sub[0].lstrip()
                lines.extend(sub)
            elif isinstance(x, list) and x:
                sub = yaml_dump(x, ind + 2).split("\n")
                sub[0] = pad + "- " + sub[0].lstrip()
                lines.extend(sub)
            else:
                lines.append("%s- %s" % (pad, _yscalar(x)))
    return "\n".join(lines)


def _yscalar(x):
    if x is None:
        return "null"
    if x is True:
        return "true"
    if x is False:
        return "false"
    if isinstance(x, dict):
        return "{}"
    if isinstance(x, list):
        return "[]"
    s = str(x)
    if isinstance(x, str) and (s == "" or re.fullmatch(r"[-+]?[0-9.]+|true|false|null", s)
                               or s[0] in "[{'\"*&!|>%@`#" or ": " in s or " #" in s):
        return '"%s"' % s.replace('"', '\\"')
    return s


# ------------------------------------------------------------------ compose model
SVC_KEYS = {"image", "container_name", "restart", "network_mode", "networks",
            "depends_on", "environment", "env_file", "volumes", "deploy", "runtime",
            "gpus", "command", "entrypoint", "ports", "healthcheck", "logging",
            "labels", "devices", "privileged", "shm_size", "ulimits", "working_dir",
            "user", "cap_add", "cap_drop", "ipc", "init", "stop_grace_period",
            "extra_hosts", "tmpfs", "profiles", "hostname", "build", "pull_policy",
            "security_opt", "group_add", "mem_limit", "cpus", "stop_signal"}
DEPLOY_KEYS = {"resources", "restart_policy", "replicas", "mode", "labels",
               "placement", "update_config", "rollback_config", "endpoint_mode"}
RES_KEYS = {"limits", "reservations"}
RESV_KEYS = {"cpus", "memory", "devices", "generic_resources", "pids"}
DEV_KEYS = {"driver", "count", "device_ids", "capabilities", "options"}
TOP_KEYS = {"name", "services", "networks", "volumes", "configs", "secrets",
            "version", "include"}


class Project:
    def __init__(self, path, pname=None):
        self.path = os.path.abspath(path)
        self.dir = os.path.dirname(self.path)
        try:
            with open(self.path) as f:
                text = f.read()
        except FileNotFoundError:
            raise DErr("open %s: no such file or directory" % self.path)
        except PermissionError:
            raise DErr("open %s: permission denied" % self.path)
        try:
            doc = yaml_load(text)
        except YErr as e:
            raise DErr(str(e))
        if not isinstance(doc, dict):
            raise DErr("validating %s: top-level object must be a mapping" % self.path)
        self.warnings = []
        for k in doc:
            if k not in TOP_KEYS and not k.startswith("x-"):
                raise DErr("validating %s: (root) additional properties '%s' not allowed"
                           % (self.path, k))
        if "version" in doc:
            self.warnings.append(
                'WARN[0000] %s: the attribute `version` is obsolete, it will be ignored, '
                'please remove it to avoid potential confusion ' % self.path)
        name = pname or doc.get("name") or os.path.basename(self.dir)
        self.name = re.sub(r"[^a-z0-9_-]", "", str(name).lower())
        svcs = doc.get("services")
        if not isinstance(svcs, dict) or not svcs:
            raise DErr("no service selected" if svcs is None else
                       "validating %s: services must be a mapping" % self.path)
        self.services = {}
        for sname, s in svcs.items():
            where = "services.%s" % sname
            if not isinstance(s, dict):
                raise DErr("validating %s: %s must be a mapping" % (self.path, where))
            for k in s:
                if k not in SVC_KEYS and not str(k).startswith("x-"):
                    raise DErr("validating %s: %s additional properties '%s' not allowed"
                               % (self.path, where, k))
            self._check_deploy(s.get("deploy"), where + ".deploy")
        for sname, s in svcs.items():
            if not s.get("image"):
                raise DErr('service "%s" has neither an image nor a build context '
                           'specified: invalid compose project' % sname)
            self.services[sname] = self._norm(sname, s)

    def _check_deploy(self, d, where):
        def chk(obj, keys, w):
            if obj is None:
                return
            if not isinstance(obj, dict):
                raise DErr("validating %s: %s must be a mapping" % (self.path, w))
            for k in obj:
                if k not in keys:
                    raise DErr("validating %s: %s additional properties '%s' not allowed"
                               % (self.path, w, k))
        chk(d, DEPLOY_KEYS, where)
        if not d:
            return
        r = d.get("resources")
        chk(r, RES_KEYS, where + ".resources")
        if not r:
            return
        for part in ("limits", "reservations"):
            chk(r.get(part), RESV_KEYS, "%s.resources.%s" % (where, part))
        rv = r.get("reservations") or {}
        devs = rv.get("devices")
        if devs is None:
            return
        if not isinstance(devs, list):
            raise DErr("validating %s: %s.resources.reservations.devices must be a list"
                       % (self.path, where))
        for i, dv in enumerate(devs):
            w = "%s.resources.reservations.devices.%d" % (where, i)
            chk(dv, DEV_KEYS, w)
            if not isinstance(dv, dict) or "capabilities" not in dv:
                raise DErr("validating %s: %s capabilities is required" % (self.path, w))
            if not isinstance(dv["capabilities"], list):
                raise DErr("validating %s: %s.capabilities must be a list" % (self.path, w))
            c = dv.get("count")
            if c is not None and c != "all" and not isinstance(c, int):
                raise DErr("services.%s.deploy.resources.reservations.devices.%d.count: "
                           'invalid value "%s", the only value allowed is \'all\' or a number'
                           % (where.split(".")[1], i, c))

    def _norm(self, sname, s):
        n = {}
        for k in sorted(s):
            v = s[k]
            if k == "environment":
                env = {}
                if isinstance(v, list):
                    for e in v:
                        e = str(e)
                        kk, _, vv = e.partition("=")
                        env[kk] = vv if "=" in e else None
                elif isinstance(v, dict):
                    for kk, vv in v.items():
                        env[kk] = None if vv is None else (
                            ("true" if vv else "false") if isinstance(vv, bool) else str(vv))
                elif v is not None:
                    raise DErr("validating %s: services.%s.environment must be a mapping"
                               % (self.path, sname))
                v = env
            elif k == "depends_on":
                if isinstance(v, list):
                    v = {d: {"condition": "service_started", "required": True} for d in v}
            elif k == "volumes":
                vols = []
                for x in v or []:
                    if isinstance(x, str):
                        parts = x.split(":")
                        src = parts[0]
                        if src.startswith("./") or src == ".":
                            src = os.path.normpath(os.path.join(self.dir, src))
                        vols.append({"type": "bind", "source": src,
                                     "target": parts[1] if len(parts) > 1 else parts[0],
                                     "read_only": len(parts) > 2 and "ro" in parts[2].split(","),
                                     "bind": {"create_host_path": True}})
                    else:
                        vols.append(x)
                v = vols
            elif k == "deploy" and isinstance(v, dict):
                v = json.loads(json.dumps(v))
                for dv in (((v.get("resources") or {}).get("reservations") or {})
                           .get("devices") or []):
                    if dv.get("count") == "all" or ("count" not in dv and "device_ids" not in dv):
                        dv["count"] = -1
                    dv["capabilities"] = [str(c) for c in dv.get("capabilities") or []]
            n[k] = v
        n.setdefault("restart", "no")
        n.setdefault("network_mode", "")
        n.setdefault("environment", {})
        return n

    def order(self, only=None):
        done, res = set(), []

        def visit(s):
            if s in done:
                return
            done.add(s)
            for d in (self.services[s].get("depends_on") or {}):
                if d in self.services:
                    visit(d)
            res.append(s)
        for s in (only or self.services):
            if s not in self.services:
                raise DErr("no such service: %s" % s)
            visit(s)
        return res

    def svc_hash(self, sname):
        return hashlib.sha256(json.dumps(self.services[sname], sort_keys=True)
                              .encode()).hexdigest()

    def cname(self, sname):
        return self.services[sname].get("container_name") or \
            "%s-%s-1" % (self.name, sname)


def find_compose_file(files, projdir=None):
    if files:
        return files[-1]
    d = os.path.abspath(projdir or os.getcwd())
    while True:
        for n in ("compose.yaml", "compose.yml", "docker-compose.yml",
                  "docker-compose.yaml"):
            if os.path.isfile(os.path.join(d, n)):
                return os.path.join(d, n)
        if d == "/":
            raise DErr("no configuration file provided: not found")
        d = os.path.dirname(d)


# ------------------------------------------------------------------ GPU resolution
def gpu_from_requests(reqs, runtime):
    """-> (visible, compute, error)"""
    if runtime not in (None, "", "runc", "nvidia", "io.containerd.runc.v2"):
        return False, False, "Error response from daemon: unknown or invalid runtime " \
                             "name: %s" % runtime
    visible = compute = False
    for r in reqs or []:
        caps = set()
        for c in r.get("Capabilities") or []:
            caps |= set(c)
        drv = r.get("Driver") or ""
        if drv not in ("", "nvidia") or not caps or not caps <= NV_CAPS:
            return False, False, "Error response from daemon: could not select device " \
                "driver \"%s\" with capabilities: [%s]" % (
                    drv, " ".join("[%s]" % " ".join(c) for c in r.get("Capabilities") or []))
        for d in r.get("DeviceIDs") or []:
            if str(d) not in ("0", "GPU-3f0c6b1e-8a52-9d47-1c0e-5b7a2d9e4f10"):
                return False, False, (
                    "Error response from daemon: failed to create task for container: "
                    "failed to create shim task: OCI runtime create failed: runc create "
                    "failed: unable to start container process: error during container "
                    "init: error running hook #0: error running hook: exit status 1, "
                    "stdout: , stderr: Auto-detected mode as 'legacy'\n"
                    "nvidia-container-cli: device error: %s: unknown device: unknown" % d)
        if r.get("Count", 0) == 0 and not r.get("DeviceIDs"):
            continue
        visible = True
        if caps & {"gpu", "nvidia", "compute"}:
            compute = True
    if runtime == "nvidia":
        visible = compute = True
    return visible, compute, None


def service_gpu(svc):
    reqs = []
    for dv in (((svc.get("deploy") or {}).get("resources") or {})
               .get("reservations") or {}).get("devices") or []:
        reqs.append({"Driver": dv.get("driver", "") or "",
                     "Count": dv.get("count", 0) if not dv.get("device_ids") else 0,
                     "DeviceIDs": [str(x) for x in dv["device_ids"]]
                     if dv.get("device_ids") else None,
                     "Capabilities": [list(dv.get("capabilities") or [])],
                     "Options": dv.get("options") or {}})
    g = svc.get("gpus")
    if g:
        reqs.append({"Driver": "nvidia", "Count": -1 if g == "all" else 0,
                     "DeviceIDs": None, "Capabilities": [["gpu"]], "Options": {}})
    return reqs or None, svc.get("runtime") or "runc"


# ------------------------------------------------------------------ state
def locked():
    if os.geteuid() != 0:
        raise DErr("Error response from daemon: (drill mock) the mock engine needs root: "
                   "use sudo docker ...")
    os.makedirs(ROOT, exist_ok=True)
    f = open(LOCK, "a")
    fcntl.flock(f, fcntl.LOCK_EX)
    return f


def load_state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except FileNotFoundError:
        return {"containers": {}}
    except PermissionError:
        raise DErr("Error response from daemon: (drill mock) the mock engine needs root: "
                   "use sudo docker ...")


def save_state(st):
    tmp = STATE + ".tmp"
    data = json.dumps(st, indent=1)
    try:
        with open(tmp, "w") as f:
            f.write(data)
        os.replace(tmp, STATE)
    except OSError:                  # full disk: rewrite in place (frees, then reuses)
        try:
            os.remove(tmp)
        except OSError:
            pass
        with open(STATE, "r+" if os.path.exists(STATE) else "w") as f:
            f.truncate(0)
            f.write(data)


def alive(pid):
    if not pid:
        return False
    try:
        with open("/proc/%d/stat" % pid) as f:
            return f.read().split(")")[-1].split()[0] != "Z"
    except OSError:
        return False


def _exit_file(c):
    return os.path.join(os.path.dirname(c["log"]), "mock-exitcode")


def _exit_of(c):
    """(code, when) the workload recorded at exit (sitecustomize), else a kill: 137"""
    try:
        with open(_exit_file(c)) as f:
            pid, code = f.read().split()[:2]
        if int(pid) == c["pid"]:
            return int(code), os.path.getmtime(_exit_file(c))
    except (OSError, ValueError):
        pass
    return 137, time.time()


def reconcile(st):
    """running containers whose process is gone -> exited; died=True marks an exit
    the engine did not ask for (the restart policy supervisor in dockerd acts on it)"""
    ch = False
    for c in st["containers"].values():
        if c["status"] == "running" and not alive(c["pid"]):
            code, when = _exit_of(c)
            c.update(status="exited", exit_code=code, finished=when, pid=0, died=True)
            ch = True
    return ch


def want_restart(c):
    name, _, n = (c.get("restart") or "no").partition(":")
    if c.get("manual_stop"):
        return False
    if name in ("always", "unless-stopped"):
        return True
    if name == "on-failure":
        return c["exit_code"] != 0 and (not n or c["restart_count"] < int(n))
    return False


def _seed_restarts(c):
    """MOCK_DOCKER_RESTARTS=name=N[,name=N]: a container that has been crash-looping
    for a while (restart count N, backoff already at N doublings of 100 ms, max 60 s)"""
    seed = dict(x.split("=", 1) for x in
                os.environ.get("MOCK_DOCKER_RESTARTS", "").split(",") if "=" in x)
    if c["name"] in seed:
        n = int(seed[c["name"]])
        c.update(restart_count=n, restart_delay=min(0.1 * 2 ** min(n, 20), 60.0))


def supervise(st):
    """one pass of dockerd's restart manager (caller holds the lock). -> changed?"""
    ch = reconcile(st)
    now = time.time()
    for c in list(st["containers"].values()):
        if c["status"] == "exited" and c.get("died"):
            c["died"] = False
            ch = True
            if want_restart(c):
                ran = c["finished"] - (c.get("spawned") or c["started"] or c["finished"])
                d = c.get("restart_delay") or 0
                d = 0.1 if (not d or ran >= 10) else min(d * 2, 60.0)
                c.update(status="restarting", restart_delay=d, restart_at=c["finished"] + d)
        if c["status"] == "restarting" and now >= c.get("restart_at", 0):
            c["restart_count"] = c.get("restart_count", 0) + 1
            try:
                spawn(c)
            except DErr:
                c.update(status="exited", exit_code=128, finished=time.time(), pid=0)
            ch = True
    return ch


def lookup(st, ref):
    ref = ref.lstrip("/")
    for c in st["containers"].values():
        if c["name"] == ref or c["id"] == ref:
            return c
    m = [c for c in st["containers"].values() if c["id"].startswith(ref)] if len(ref) >= 1 \
        else []
    return m[0] if len(m) == 1 else None


def new_id():
    return hashlib.sha256(os.urandom(32)).hexdigest()


def make_container(st, name, image, env, cmd, labels, restart, netmode, binds,
                   runtime, devreqs, created=None, workdir=None, logcfg=None):
    img = IMAGES[image]
    cid = new_id()
    d = os.path.join(ROOT, "containers", cid)
    os.makedirs(d, exist_ok=True)
    c = dict(id=cid, name=name, image=image, image_id="sha256:" + img["id"],
             kind=img["kind"], env=env, cmd=cmd, labels=labels, restart=restart,
             netmode=netmode or "bridge", binds=binds, runtime=runtime or "runc",
             devreqs=devreqs, created=created or time.time(), started=0, finished=0,
             status="created", pid=0, exit_code=0, restart_count=0,
             workdir=workdir or img["workdir"],
             log=os.path.join(d, cid + "-json.log"),
             logcfg=logcfg or daemon_logcfg())
    st["containers"][cid] = c
    return c


def spawn(c, backdate=None):
    """start the container's process in its own scope, like runc does"""
    vis, comp, err = gpu_from_requests(c["devreqs"], c["runtime"])
    if err:
        raise DErr(err)
    env = [e for e in c["env"] if "=" in e]
    mod = c["kind"] if has_workload(c["kind"]) else None
    if not mod:
        raise DErr("Error response from daemon: container %s: no long-running process"
                   % c["id"][:12])
    hidden = ["PYTHONPATH=" + WORKLIB, "PYTHONDONTWRITEBYTECODE=1",
              "MOCKD_ID=" + c["id"], "MOCKD_LOG=" + c["log"],
              "MOCKD_GPU=%d" % (1 if comp else 0), "MOCKD_NAME=" + c["name"],
              "MOCKD_IMAGE=" + c["image"], "MOCKD_EXIT=" + _exit_file(c),
              "MOCKD_RESTARTS=%d" % c.get("restart_count", 0),
              "MOCKD_CMD=" + json.dumps(c["cmd"]),
              "MOCKD_BINDS=" + json.dumps(c["binds"] or [])]
    if (c.get("logcfg") or {}).get("Type") == "none":
        hidden[3] = "MOCKD_LOG=/dev/null"
    if backdate:
        hidden.append("MOCKD_BACKDATE=%d" % backdate)
    argv = ["env", "-i"] + env + hidden + ["python3", "-m", mod] + \
        (c["cmd"][3:] if c["cmd"][:3] == ["python3", "-m", mod] else [])
    unit = "docker-%s.scope" % c["id"]
    for _ in range(50):                      # an old scope of the same id may still be dying
        if subprocess.run(["systemctl", "is-active", "--quiet", unit]).returncode != 0:
            break
        time.sleep(0.1)
    try:
        p = subprocess.Popen(["systemd-run", "--scope", "--quiet", "--collect",
                              "--unit=" + unit,
                              "--description=libcontainer container " + c["id"],
                              "--"] + argv,
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True,
                             cwd="/")
    except FileNotFoundError:
        p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True, cwd="/")
    # wait until it is really running (and, on the GPU, visible to nvidia-smi)
    gpu_file = os.path.join(GPU_DIR, c["name"] + ".json")
    for _ in range(60):
        time.sleep(0.1)
        if p.poll() is not None:
            break
        if os.path.exists(c["log"]) and os.path.getsize(c["log"]) > 0:
            if c["kind"] != "vehiclecount" or not comp or _gpu_pid(gpu_file) == p.pid:
                break
    c.update(status="running", pid=p.pid, started=time.time(), spawned=time.time(),
             exit_code=0, died=False)
    if p.poll() is not None:
        rc = p.returncode
        c.update(status="exited", pid=0, exit_code=(128 - rc) if rc < 0 else (rc or 1),
                 finished=time.time(), died=True)


def _gpu_pid(path):
    try:
        with open(path) as f:
            return json.load(f).get("pid")
    except (OSError, ValueError):
        return None


def stop(c, timeout=10):
    c["died"] = False
    if c["status"] == "restarting":
        c.update(status="exited", pid=0)
        return
    if c["status"] != "running" or not alive(c["pid"]):
        if c["status"] == "running":
            c.update(status="exited", exit_code=137, finished=time.time(), pid=0)
        return
    pid = c["pid"]
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    code = 0
    t0 = time.time()
    while alive(pid) and time.time() - t0 < timeout:
        time.sleep(0.05)
    if alive(pid):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        code = 137
        while alive(pid):
            time.sleep(0.05)
    gf = os.path.join(GPU_DIR, c["name"] + ".json")
    if _gpu_pid(gf) == pid:
        try:
            os.remove(gf)
        except OSError:
            pass
    c.update(status="exited", exit_code=code, finished=time.time(), pid=0)


def remove(st, c):
    stop(c, 10)
    st["containers"].pop(c["id"], None)
    d = os.path.dirname(c["log"])
    try:
        for f in os.listdir(d):
            os.remove(os.path.join(d, f))
        os.rmdir(d)
    except OSError:
        pass


# ------------------------------------------------------------------ formatting
def human(d):
    s = int(d)
    if s < 1:
        return "Less than a second"
    if s == 1:
        return "1 second"
    if s < 60:
        return "%d seconds" % s
    m = int(d / 60)
    if m == 1:
        return "About a minute"
    if m < 60:
        return "%d minutes" % m
    h = int(d / 3600 + 0.5)
    if h == 1:
        return "About an hour"
    if h < 48:
        return "%d hours" % h
    if h < 24 * 7 * 2:
        return "%d days" % (h // 24)
    if h < 24 * 30 * 2:
        return "%d weeks" % (h // 24 // 7)
    if h < 24 * 365 * 2:
        return "%d months" % (h // 24 // 30)
    return "%d years" % (h // 24 // 365)


def status_str(c):
    now = time.time()
    if c["status"] == "running":
        return "Up " + human(now - c["started"])
    if c["status"] == "created":
        return "Created"
    if c["status"] == "restarting":
        return "Restarting (%d) %s ago" % (c["exit_code"], human(now - c["finished"]))
    return "Exited (%d) %s ago" % (c["exit_code"], human(now - c["finished"]))


def iso(t):
    if not t:
        return "0001-01-01T00:00:00Z"
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + \
        (".%09dZ" % int((t % 1) * 1e9))


def ellipsis(s, n):
    return s if len(s) <= n else s[:n - 1] + "…"


def table(rows):
    """docker's tabwriter: minwidth 10, padding 3"""
    if not rows:
        return
    w = [0] * len(rows[0])
    for r in rows:
        for i, x in enumerate(r[:-1]):
            w[i] = max(w[i], len(x) + 3, 10)
    for r in rows:
        out("".join(x.ljust(w[i]) if i < len(r) - 1 else x for i, x in enumerate(r)).rstrip())


def cmdline(c):
    return " ".join(c["cmd"])


def ps_ctx(c, trunc=True):
    lab = c["labels"] or {}
    return {
        "ID": c["id"][:12] if trunc else c["id"],
        "Image": c["image"],
        "Command": '"%s"' % (ellipsis(cmdline(c), 20) if trunc else cmdline(c)),
        "CreatedAt": time.strftime("%Y-%m-%d %H:%M:%S %z %Z", time.localtime(c["created"])),
        "RunningFor": human(time.time() - c["created"]) + " ago",
        "Ports": "",
        "State": c["status"],
        "Status": status_str(c),
        "Names": c["name"],
        "Labels": ",".join("%s=%s" % kv for kv in sorted(lab.items())),
        "Mounts": ",".join(b.split(":")[0].rstrip("/").split("/")[-1] if b.startswith("/")
                           else b.split(":")[0] for b in c["binds"]),
        "Networks": c["netmode"],
        "Size": "0B",
        "LocalVolumes": "0",
        "Service": lab.get("com.docker.compose.service", ""),
        "Project": lab.get("com.docker.compose.project", ""),
        "Name": c["name"],
    }


HEADERS = {"ID": "CONTAINER ID", "Image": "IMAGE", "Command": "COMMAND",
           "CreatedAt": "CREATED AT", "RunningFor": "CREATED", "Ports": "PORTS",
           "State": "STATE", "Status": "STATUS", "Names": "NAMES", "Labels": "LABELS",
           "Mounts": "MOUNTS", "Networks": "NETWORKS", "Size": "SIZE",
           "Service": "SERVICE", "Project": "PROJECT", "Name": "NAME",
           "Repository": "REPOSITORY", "Tag": "TAG", "CreatedSince": "CREATED",
           "LocalVolumes": "LOCAL VOLUMES"}


def inspect_obj(c):
    lab = c["labels"] or {}
    mounts = []
    for b in c["binds"]:
        p = b.split(":")
        mounts.append({"Type": "bind", "Source": p[0], "Destination": p[1],
                       "Mode": p[2] if len(p) > 2 else "", "RW": not (len(p) > 2 and
                                                                     "ro" in p[2]),
                       "Propagation": "rprivate"})
    rp = c["restart"] or "no"
    running = c["status"] == "running"
    return {
        "Id": c["id"],
        "Created": iso(c["created"]),
        "Path": c["cmd"][0],
        "Args": c["cmd"][1:],
        "State": {
            "Status": c["status"], "Running": running, "Paused": False,
            "Restarting": c["status"] == "restarting", "OOMKilled": False, "Dead": False,
            "Pid": c["pid"] if running else 0, "ExitCode": c["exit_code"], "Error": "",
            "StartedAt": iso(c["started"]), "FinishedAt": iso(c["finished"])},
        "Image": c["image_id"],
        "ResolvConfPath": "/var/lib/docker/containers/%s/resolv.conf" % c["id"],
        "HostnamePath": "/var/lib/docker/containers/%s/hostname" % c["id"],
        "HostsPath": "/var/lib/docker/containers/%s/hosts" % c["id"],
        "LogPath": c["log"],
        "Name": "/" + c["name"],
        "RestartCount": c["restart_count"],
        "Driver": "overlay2",
        "Platform": "linux",
        "MountLabel": "",
        "ProcessLabel": "",
        "AppArmorProfile": "",
        "ExecIDs": None,
        "HostConfig": {
            "Binds": c["binds"] or None,
            "ContainerIDFile": "",
            "LogConfig": c.get("logcfg") or {"Type": "json-file", "Config": {}},
            "NetworkMode": c["netmode"],
            "PortBindings": {},
            "RestartPolicy": {"Name": rp, "MaximumRetryCount": 0},
            "AutoRemove": False,
            "VolumeDriver": "",
            "VolumesFrom": None,
            "CapAdd": None,
            "CapDrop": None,
            "Privileged": False,
            "Runtime": c["runtime"],
            "ShmSize": 67108864,
            "Memory": 0,
            "NanoCpus": 0,
            "Devices": None,
            "DeviceRequests": c["devreqs"],
        },
        "GraphDriver": {"Data": {}, "Name": "overlay2"},
        "Mounts": mounts,
        "Config": {
            "Hostname": HOST if c["netmode"] == "host" else c["id"][:12],
            "Domainname": "",
            "User": "",
            "AttachStdin": False, "AttachStdout": False, "AttachStderr": False,
            "Tty": False, "OpenStdin": False, "StdinOnce": False,
            "Env": c["env"],
            "Cmd": c["cmd"],
            "Image": c["image"],
            "Volumes": None,
            "WorkingDir": c["workdir"],
            "Entrypoint": None,
            "OnBuild": None,
            "Labels": lab,
        },
        "NetworkSettings": {
            "Bridge": "", "SandboxID": "", "Ports": {},
            "Networks": {c["netmode"]: {"NetworkID": hashlib.sha256(
                c["netmode"].encode()).hexdigest(), "Gateway": "", "IPAddress": "",
                "MacAddress": ""}}},
    }


# ------------------------------------------------------------------ Go templates (subset)
MAPS = {"Labels", "Options", "Ports", "Networks", "PortBindings", "Config", "Data",
        "ExposedPorts", "Volumes"}
SLICES = {"DeviceRequests", "DeviceIDs", "Capabilities", "Binds", "Env", "Cmd", "Args",
          "Mounts", "Devices", "CapAdd", "CapDrop", "VolumesFrom", "Entrypoint",
          "ExecIDs", "OnBuild"}


class TErr(Exception):
    pass


def gofmt(v, key=None):
    if v is None:
        return "[]" if key in SLICES else "map[]" if key in MAPS else "<nil>"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, float):
        return ("%d" % v) if v == int(v) else repr(v)
    if isinstance(v, list):
        return "[" + " ".join(gofmt(x) for x in v) + "]"
    if isinstance(v, dict):
        if key in MAPS:
            return "map[" + " ".join("%s:%s" % (k, gofmt(v[k], k)) for k in sorted(v)) + "]"
        return "{" + " ".join(gofmt(x, k) for k, x in v.items()) + "}"
    return str(v)


def tmpl(src, data):
    toks = re.split(r"({{-?.*?-?}})", src)
    nodes, stack = [], []
    cur = nodes
    col = 0
    for t in toks:
        if t.startswith("{{"):
            a = t[2:-2].strip("- ").strip()
            w = a.split(None, 1)
            if w and w[0] in ("range", "if", "with"):
                n = {"op": w[0], "arg": w[1] if len(w) > 1 else "", "body": [],
                     "else": None, "col": col + 3}
                cur.append(n)
                stack.append((n, cur))
                cur = n["body"]
            elif a == "else":
                if not stack:
                    raise TErr('template parsing error: template: :1: unexpected {{else}}')
                stack[-1][0]["else"] = []
                cur = stack[-1][0]["else"]
            elif a == "end":
                if not stack:
                    raise TErr('template parsing error: template: :1: unexpected {{end}}')
                cur = stack.pop()[1]
            else:
                cur.append({"op": "expr", "arg": a, "col": col + 3})
        elif t:
            cur.append(t)
        col += len(t)
    if stack:
        raise TErr('template parsing error: template: :1: unexpected EOF')
    return "".join(_run(nodes, data, data))


FUNCS = {"json", "index", "upper", "lower", "join", "println", "print", "len",
         "title", "split", "truncate", "pad", "printf", "eq", "ne", "not", "and", "or"}


def _args(s):
    try:
        return shlex.split(s, posix=True)
    except ValueError:
        raise TErr("template parsing error: template: :1: unterminated quoted string")


def _field(path, dot, col):
    if path == ".":
        return dot, None
    cur, key, walked = dot, None, ""
    for p in path.strip(".").split("."):
        walked += "." + p
        if isinstance(cur, dict):
            if p not in cur:
                raise TErr('template: :1:%d: executing "" at <%s>: map has no entry for '
                           'key "%s"' % (col, path, p))
            cur, key = cur[p], p
        elif cur is None:
            raise TErr('template: :1:%d: executing "" at <%s>: nil pointer evaluating '
                       'interface {}.%s' % (col, path, p))
        else:
            raise TErr('template: :1:%d: executing "" at <%s>: can\'t evaluate field %s '
                       'in type %s' % (col, path, p, type(cur).__name__))
    return cur, key


def _eval(expr, dot, col):
    a = _args(expr)
    if not a:
        return "", None
    f = a[0]
    if f.startswith("."):
        if len(a) > 1:
            raise TErr('template: :1:%d: executing "" at <%s>: %s is not a method but has '
                       'arguments' % (col, f, f))
        return _field(f, dot, col)
    if f.startswith("$"):
        return _field("." + f[1:].lstrip("."), dot, col) if f != "$" else (dot, None)
    if f not in FUNCS:
        raise TErr('template parsing error: template: :1: function "%s" not defined' % f)
    vals = []
    for x in a[1:]:
        if x.startswith("."):
            vals.append(_field(x, dot, col))
        else:
            vals.append((int(x) if re.fullmatch(r"-?\d+", x) else x, None))
    if f == "json":
        v = vals[0][0] if vals else dot
        return json.dumps(v, separators=(",", ":"), ensure_ascii=False), "raw"
    if f == "index":
        v = vals[0][0]
        for k, _ in vals[1:]:
            try:
                v = v[k]
            except (KeyError, IndexError, TypeError):
                if isinstance(v, dict):
                    v = None
                else:
                    raise TErr('template: :1:%d: executing "" at <index %s>: error calling '
                               'index: index out of range: %s' % (col, a[1], k))
        return v, None
    if f in ("upper", "lower", "title"):
        s = gofmt(vals[0][0], vals[0][1])
        return getattr(s, f)(), "raw"
    if f == "join":
        return (vals[1][0] if len(vals) > 1 else "").join(
            gofmt(x) for x in (vals[0][0] or [])), "raw"
    if f == "len":
        return len(vals[0][0] or []), None
    if f == "println":
        return " ".join(gofmt(v, k) for v, k in vals) + "\n", "raw"
    if f in ("print", "printf"):
        return " ".join(gofmt(v, k) for v, k in vals), "raw"
    if f == "split":
        return str(vals[0][0]).split(vals[1][0]), None
    if f in ("eq", "ne"):
        r = gofmt(vals[0][0]) == gofmt(vals[1][0])
        return (r if f == "eq" else not r), None
    if f == "not":
        return not vals[0][0], None
    if f in ("and", "or"):
        r = all(v for v, _ in vals) if f == "and" else any(v for v, _ in vals)
        return r, None
    return gofmt(vals[0][0]) if vals else "", "raw"


def _run(nodes, dot, root):
    res = []
    for n in nodes:
        if isinstance(n, str):
            res.append(n)
            continue
        if n["op"] == "expr":
            v, k = _eval(n["arg"], dot, n["col"])
            res.append(v if k == "raw" else gofmt(v, k))
            continue
        v, _ = _eval(n["arg"], dot, n["col"])
        if n["op"] == "range":
            items = list(v.values()) if isinstance(v, dict) else (v or [])
            if items:
                for it in items:
                    res.extend(_run(n["body"], it, root))
            elif n["else"] is not None:
                res.extend(_run(n["else"], dot, root))
        elif n["op"] == "if":
            if v:
                res.extend(_run(n["body"], dot, root))
            elif n["else"] is not None:
                res.extend(_run(n["else"], dot, root))
        elif n["op"] == "with":
            if v:
                res.extend(_run(n["body"], v, root))
            elif n["else"] is not None:
                res.extend(_run(n["else"], dot, root))
    return res


def fmt_rows(fmt, ctxs):
    """docker ps/images --format, with the `table` prefix"""
    fmt = fmt.replace("\\t", "\t").replace("\\n", "\n")
    is_table = fmt.startswith("table")
    if fmt in ("json", "{{json .}}"):
        for c in ctxs:
            out(json.dumps(c, separators=(",", ":")))
        return
    if is_table:
        fmt = fmt[5:].lstrip()
        hdr = re.sub(r"{{\s*\.(\w+)\s*}}", lambda m: HEADERS.get(m.group(1), m.group(1).upper()), fmt)
        rows = [hdr.split("\t")]
        for c in ctxs:
            rows.append(tmpl(fmt, c).split("\t"))
        table(rows)
    else:
        for c in ctxs:
            out(tmpl(fmt, c))


# ------------------------------------------------------------------ logs
def read_log(c):
    if (c.get("logcfg") or {}).get("Type") not in (None, "json-file", "local", "journald"):
        raise DErr('Error response from daemon: configured logging driver does not '
                   'support reading')
    _, mf = log_limits(c)
    for fn in ["%s.%d" % (c["log"], i) for i in range(mf - 1, 0, -1)] + [c["log"]]:
        try:
            with open(fn) as f:
                for line in f:
                    try:
                        yield json.loads(line)
                    except ValueError:
                        continue
        except FileNotFoundError:
            continue


def parse_since(s):
    m = re.fullmatch(r"(\d+)(s|m|h)", s)
    if m:
        return time.time() - int(m.group(1)) * {"s": 1, "m": 60, "h": 3600}[m.group(2)]
    for f in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
        try:
            return time.mktime(time.strptime(s, f))
        except ValueError:
            pass
    if re.fullmatch(r"\d+(\.\d+)?", s):
        return float(s)
    raise DErr('invalid value for "since": failed to parse value as time or '
               'duration: "%s"' % s)


def rec_time(rec):
    try:
        return calendar.timegm(time.strptime(rec.get("time", "")[:19], "%Y-%m-%dT%H:%M:%S"))
    except ValueError:
        return 0


def emit(rec, stamps, prefix=""):
    line = rec.get("log", "")
    s = prefix + ((rec.get("time", "") + " ") if stamps else "") + line
    stream = sys.stderr if rec.get("stream") == "stderr" else sys.stdout
    stream.write(s)
    stream.flush()


def follow(conts, stamps, prefixes=None):
    offs = {}
    for c in conts:
        try:
            offs[c["id"]] = os.path.getsize(c["log"])
        except OSError:
            offs[c["id"]] = 0
    try:
        while True:
            time.sleep(0.5)
            anyalive = False
            for c in conts:
                try:
                    with open(c["log"]) as f:
                        f.seek(offs[c["id"]])
                        data = f.read()
                        offs[c["id"]] = f.tell()
                except OSError:
                    data = ""
                for line in data.splitlines():
                    try:
                        emit(json.loads(line), stamps, (prefixes or {}).get(c["id"], ""))
                    except ValueError:
                        pass
                if alive(c["pid"]):
                    anyalive = True
            if not anyalive:
                return 0
    except KeyboardInterrupt:
        return 130


# ------------------------------------------------------------------ access
def need_daemon(endpoint="containers/json", method="Get"):
    if not os.path.exists(SOCK):
        raise DErr("Cannot connect to the Docker daemon at unix://%s. Is the docker "
                   "daemon running?" % SOCK)
    if not os.access(SOCK, os.R_OK | os.W_OK):
        raise DErr('permission denied while trying to connect to the Docker daemon '
                   'socket at unix://%s: %s "http://%%2Fvar%%2Frun%%2Fdocker.sock/v%s/%s": '
                   'dial unix %s: connect: permission denied' % (SOCK, method, API,
                                                                 endpoint, SOCK))


def ensure_root_state():
    if os.geteuid() != 0:
        # group docker would really work; the mock needs root to manage processes
        raise DErr("Error response from daemon: (drill mock) the mock engine needs root: "
                   "use sudo docker ...")


# ------------------------------------------------------------------ flag parsing
def getopts(args, spec, cmdname):
    """spec: {flag: takes_value}. Returns (opts{canonical: [values]}, positionals)."""
    opts, pos, i = {}, [], 0
    alias = {}
    for k in list(spec):
        for a in k.split("|"):
            alias[a] = k
    while i < len(args):
        a = args[i]
        if a == "--":
            pos.extend(args[i + 1:])
            break
        if a.startswith("--") and len(a) > 2:
            name, eq, val = a.partition("=")
            if name not in alias:
                raise DErr("unknown flag: %s\nSee '%s --help'." % (name, cmdname), 125)
            k = alias[name]
            if spec[k]:
                if not eq:
                    i += 1
                    if i >= len(args):
                        raise DErr("flag needs an argument: %s\nSee '%s --help'."
                                   % (name, cmdname), 125)
                    val = args[i]
                opts.setdefault(k, []).append(val)
            else:
                opts.setdefault(k, []).append(True)
        elif a.startswith("-") and len(a) > 1 and not pos_stop(pos, spec):
            j = 1
            while j < len(a):
                f = "-" + a[j]
                if f not in alias:
                    raise DErr("unknown shorthand flag: '%s' in %s\nSee '%s --help'."
                               % (a[j], a, cmdname), 125)
                k = alias[f]
                if spec[k]:
                    val = a[j + 1:].lstrip("=")
                    if not val:
                        i += 1
                        if i >= len(args):
                            raise DErr("flag needs an argument: '%s' in %s\nSee '%s --help'."
                                       % (a[j], a, cmdname), 125)
                        val = args[i]
                    opts.setdefault(k, []).append(val)
                    break
                opts.setdefault(k, []).append(True)
                j += 1
        else:
            pos.append(a)
        i += 1
    return opts, pos


def pos_stop(pos, spec):
    return False


# ------------------------------------------------------------------ commands
def cmd_ps(args, compose_proj=None):
    o, p = getopts(args, {"-a|--all": False, "-q|--quiet": False, "--no-trunc": False,
                          "-f|--filter": True, "--format": True, "-s|--size": False,
                          "-n|--last": True, "-l|--latest": False}, "docker ps")
    need_daemon()
    st = load_state()
    reconcile(st)
    cs = sorted(st["containers"].values(), key=lambda c: -c["created"])
    if "-a|--all" not in o:
        cs = [c for c in cs if c["status"] in ("running", "restarting")]
    for f in o.get("-f|--filter", []):
        k, _, v = f.partition("=")
        if k == "name":
            cs = [c for c in cs if re.search(v, c["name"])]
        elif k == "status":
            cs = [c for c in cs if c["status"] == v]
        elif k == "label":
            lk, _, lv = v.partition("=")
            cs = [c for c in cs if lk in (c["labels"] or {}) and
                  (not lv or c["labels"][lk] == lv)]
        elif k == "ancestor":
            cs = [c for c in cs if c["image"].startswith(v)]
        else:
            raise DErr('Error response from daemon: invalid filter \'%s\'' % k)
    if "-l|--latest" in o:
        cs = cs[:1]
    trunc = "--no-trunc" not in o
    if "-q|--quiet" in o:
        for c in cs:
            out(c["id"][:12] if trunc else c["id"])
        return 0
    ctx = [ps_ctx(c, trunc) for c in cs]
    if "--format" in o:
        fmt_rows(o["--format"][-1], ctx)
        return 0
    rows = [["CONTAINER ID", "IMAGE", "COMMAND", "CREATED", "STATUS", "PORTS", "NAMES"]]
    for x in ctx:
        rows.append([x["ID"], x["Image"], x["Command"], x["RunningFor"], x["Status"],
                     x["Ports"], x["Names"]])
    table(rows)
    return 0


def cmd_images(args):
    o, p = getopts(args, {"-a|--all": False, "-q|--quiet": False, "--format": True,
                          "--no-trunc": False, "-f|--filter": True, "--digests": False},
                   "docker images")
    need_daemon("images/json")
    rows = [["REPOSITORY", "TAG", "IMAGE ID", "CREATED", "SIZE"]]
    now = time.time()
    ctxs = []
    for ref, img in sorted(catalogue().items(), key=lambda kv: kv[1]["age"]):
        repo, _, tag = ref.rpartition(":")
        if img.get("dangling"):
            repo = tag = "<none>"
        if p and not ref.startswith(p[0]):
            continue
        ctxs.append({"Repository": repo, "Tag": tag, "ID": img["id"][:12],
                     "CreatedSince": human(img["age"]) + " ago", "Size": img["size"],
                     "CreatedAt": time.strftime("%Y-%m-%d %H:%M:%S %z %Z",
                                                time.localtime(now - img["age"]))})
    if "-q|--quiet" in o:
        for c in ctxs:
            out(c["ID"])
        return 0
    if "--format" in o:
        fmt_rows(o["--format"][-1], ctxs)
        return 0
    for c in ctxs:
        rows.append([c["Repository"], c["Tag"], c["ID"], c["CreatedSince"], c["Size"]])
    table(rows)
    return 0


def cmd_inspect(args):
    o, p = getopts(args, {"-f|--format": True, "-s|--size": False, "--type": True},
                   "docker inspect")
    if not p:
        raise DErr('"docker inspect" requires at least 1 argument.\nSee \'docker inspect '
                   '--help\'.\n\nUsage:  docker inspect [OPTIONS] NAME|ID [NAME|ID...]\n\n'
                   'Return low-level information on Docker objects', 1)
    need_daemon("containers/%s/json" % p[0])
    st = load_state()
    reconcile(st)
    objs, missing = [], []
    for ref in p:
        c = lookup(st, ref)
        if c:
            objs.append(inspect_obj(c))
        elif ref in catalogue() or ref + ":latest" in catalogue():
            ref = ref if ref in catalogue() else ref + ":latest"
            img = IMAGES[ref]
            objs.append({"Id": "sha256:" + img["id"], "RepoTags": [ref],
                         "Config": {"Env": img["env"], "Cmd": img["cmd"],
                                    "WorkingDir": img["workdir"], "Labels": None},
                         "Size": 0})
        else:
            missing.append(ref)
    if "-f|--format" in o:
        f = o["-f|--format"][-1]
        try:
            for ob in objs:
                out(tmpl(f, ob))
        except TErr as e:
            raise DErr(str(e))
    else:
        out(json.dumps(objs, indent=4, ensure_ascii=False))
    if missing:
        for m in missing:
            sys.stderr.write("Error: No such object: %s\n" % m)
        return 1
    return 0


def cmd_logs(args):
    o, p = getopts(args, {"-f|--follow": False, "-n|--tail": True, "-t|--timestamps": False,
                          "--since": True, "--until": True, "--details": False},
                   "docker logs")
    if len(p) != 1:
        raise DErr('"docker logs" requires exactly 1 argument.\nSee \'docker logs --help\'.'
                   '\n\nUsage:  docker logs [OPTIONS] CONTAINER\n\nFetch the logs of a '
                   'container')
    need_daemon("containers/%s/logs" % p[0])
    st = load_state()
    reconcile(st)
    c = lookup(st, p[0])
    if not c:
        raise DErr("Error response from daemon: No such container: %s" % p[0])
    recs = list(read_log(c))
    if "--since" in o:
        t0 = parse_since(o["--since"][-1])
        recs = [r for r in recs if rec_time(r) >= t0]
    tail = o.get("-n|--tail", ["all"])[-1]
    if tail != "all":
        try:
            n = int(tail)
        except ValueError:
            raise DErr('Error response from daemon: invalid value for "tail": "%s"' % tail)
        recs = recs[-n:] if n > 0 else ([] if n == 0 else recs)
    stamps = "-t|--timestamps" in o
    for r in recs:
        emit(r, stamps)
    if "-f|--follow" in o and c["status"] == "running":
        return follow([c], stamps)
    return 0


def _names_cmd(args, verb, spec=None):
    o, p = getopts(args, spec or {"-t|--time": True, "-s|--signal": True}, "docker " + verb)
    if not p:
        raise DErr('"docker %s" requires at least 1 argument.\nSee \'docker %s --help\'.'
                   % (verb, verb))
    need_daemon("containers/%s/%s" % (p[0], verb))
    ensure_root_state()
    return o, p


def cmd_restart(args):
    o, p = _names_cmd(args, "restart")
    rc = 0
    with locked():
        st = load_state()
        reconcile(st)
        for ref in p:
            c = lookup(st, ref)
            if not c:
                sys.stderr.write("Error response from daemon: No such container: %s\n" % ref)
                rc = 1
                continue
            stop(c, int(o.get("-t|--time", [10])[-1]))
            try:
                spawn(c)
            except DErr as e:
                sys.stderr.write(e.msg + "\n")
                rc = 1
                continue
            out(ref)
        save_state(st)
    return rc


def cmd_stop(args):
    o, p = _names_cmd(args, "stop")
    rc = 0
    with locked():
        st = load_state()
        reconcile(st)
        for ref in p:
            c = lookup(st, ref)
            if not c:
                sys.stderr.write("Error response from daemon: No such container: %s\n" % ref)
                rc = 1
                continue
            stop(c, int(o.get("-t|--time", [10])[-1]))
            c["manual_stop"] = True
            out(ref)
        save_state(st)
    return rc


def cmd_start(args):
    o, p = _names_cmd(args, "start", {"-a|--attach": False, "-i|--interactive": False})
    rc = 0
    with locked():
        st = load_state()
        reconcile(st)
        for ref in p:
            c = lookup(st, ref)
            if not c:
                sys.stderr.write("Error response from daemon: No such container: %s\n" % ref)
                rc = 1
                continue
            if c["status"] != "running":
                try:
                    spawn(c)
                except DErr as e:
                    sys.stderr.write(e.msg + "\nError: failed to start containers: %s\n" % ref)
                    rc = 1
                    continue
            c["manual_stop"] = False
            out(ref)
        save_state(st)
    return rc


def cmd_rm(args):
    o, p = _names_cmd(args, "rm", {"-f|--force": False, "-v|--volumes": False,
                                   "-l|--link": False})
    rc = 0
    with locked():
        st = load_state()
        reconcile(st)
        for ref in p:
            c = lookup(st, ref)
            if not c:
                sys.stderr.write("Error response from daemon: No such container: %s\n" % ref)
                rc = 1
                continue
            if c["status"] in ("running", "restarting") and "-f|--force" not in o:
                sys.stderr.write(
                    "Error response from daemon: cannot remove container \"/%s\": container "
                    "is %s: stop the container before removing or force remove\n"
                    % (c["name"], c["status"]))
                rc = 1
                continue
            remove(st, c)
            out(ref)
        save_state(st)
    return rc


def cmd_top(args):
    if not args:
        raise DErr('"docker top" requires at least 1 argument.')
    need_daemon()
    st = load_state()
    reconcile(st)
    c = lookup(st, args[0])
    if not c:
        raise DErr("Error response from daemon: No such container: %s" % args[0])
    if c["status"] == "restarting":
        raise DErr("Error response from daemon: Container %s is restarting, wait until the "
                   "container is running" % c["id"])
    if c["status"] != "running":
        raise DErr("Error response from daemon: container %s is not running" % c["id"])
    r = subprocess.run(["ps", "-o", "user,pid,ppid,c,stime,tty,time,cmd", "--ppid",
                        str(c["pid"]), "-p", str(c["pid"])], capture_output=True, text=True)
    lines = r.stdout.splitlines()
    out("UID                 PID                 PPID                C                   "
        "STIME               TTY                 TIME                CMD")
    for ln in lines[1:]:
        f = ln.split(None, 7)
        out("".join(x.ljust(20) for x in f[:7]) + (f[7] if len(f) > 7 else ""))
    return 0


def _cpu_ticks(pid):
    try:
        with open("/proc/%d/stat" % pid) as f:
            x = f.read().split(")")[-1].split()
        return int(x[11]) + int(x[12])
    except OSError:
        return 0


def _rss(pid):
    try:
        with open("/proc/%d/status" % pid) as f:
            for ln in f:
                if ln.startswith("VmRSS:"):
                    return int(ln.split()[1]) * 1024
    except OSError:
        pass
    return 0


def _bytes(n):
    for u in ("B", "KiB", "MiB", "GiB"):
        if n < 1024 or u == "GiB":
            return ("%.4g%s" % (n, u)) if u != "B" else "%dB" % n
        n /= 1024.0


def cmd_stats(args):
    o, p = getopts(args, {"--no-stream": False, "-a|--all": False, "--format": True,
                          "--no-trunc": False}, "docker stats")
    need_daemon("containers/json")
    total = 0
    with open("/proc/meminfo") as f:
        total = int(f.readline().split()[1]) * 1024
    hz = os.sysconf("SC_CLK_TCK")
    try:
        while True:
            st = load_state()
            reconcile(st)
            cs = [c for c in st["containers"].values() if c["status"] == "running"]
            if p:
                cs = [lookup(st, x) for x in p]
                if None in cs:
                    raise DErr("Error response from daemon: No such container: %s"
                               % p[cs.index(None)])
            a = {c["id"]: _cpu_ticks(c["pid"]) for c in cs}
            time.sleep(1.0)
            b = {c["id"]: _cpu_ticks(c["pid"]) for c in cs}
            rows = [["CONTAINER ID", "NAME", "CPU %", "MEM USAGE / LIMIT", "MEM %",
                     "NET I/O", "BLOCK I/O", "PIDS"]]
            for c in sorted(cs, key=lambda c: c["name"]):
                cpu = (b[c["id"]] - a[c["id"]]) * 100.0 / hz
                rss = _rss(c["pid"])
                rows.append([c["id"][:12], c["name"], "%.2f%%" % cpu,
                             "%s / %s" % (_bytes(rss), _bytes(total)),
                             "%.2f%%" % (rss * 100.0 / total), "0B / 0B", "0B / 0B", "1"])
            if "--no-stream" not in o and sys.stdout.isatty():
                sys.stdout.write("\033[2J\033[H")
            table(rows)
            sys.stdout.flush()
            if "--no-stream" in o:
                return 0
    except KeyboardInterrupt:
        return 130


def cmd_exec(args):
    # everything after the container name belongs to the command
    raw, i = args, 0
    while i < len(raw) and raw[i].startswith("-"):
        if raw[i] in ("-u", "--user", "-e", "--env", "-w", "--workdir"):
            i += 1
        i += 1
    if len(raw) - i < 2:
        raise DErr('"docker exec" requires at least 2 arguments.\nSee \'docker exec '
                   '--help\'.\n\nUsage:  docker exec [OPTIONS] CONTAINER COMMAND [ARG...]'
                   '\n\nExecute a command in a running container')
    name, cmd = raw[i], raw[i + 1:]
    need_daemon("containers/%s/exec" % name, "Post")
    st = load_state()
    reconcile(st)
    c = lookup(st, name)
    if not c:
        raise DErr("Error response from daemon: No such container: %s" % name)
    if c["status"] == "restarting":
        raise DErr("Error response from daemon: Container %s is restarting, wait until the "
                   "container is running" % c["id"])
    if c["status"] != "running":
        raise DErr("Error response from daemon: container %s is not running" % c["id"])
    return run_in(c, cmd)


def run_in(c, cmd):
    vis, comp, _ = gpu_from_requests(c["devreqs"], c["runtime"])
    env = dict(e.split("=", 1) for e in c["env"] if "=" in e)
    if env.get("NVIDIA_VISIBLE_DEVICES", "all") in ("", "void", "none"):
        vis = comp = False
    prog = cmd[0]
    base = os.path.basename(prog)
    notfound = DErr('OCI runtime exec failed: exec failed: unable to start container '
                    'process: exec: "%s": executable file not found in $PATH: unknown'
                    % prog, 126)
    if base == "nvidia-smi":
        if not vis:
            raise notfound
        return subprocess.run(["nvidia-smi"] + cmd[1:]).returncode
    if base in ("env", "printenv"):
        e = dict(env)
        e.setdefault("HOSTNAME", HOST if c["netmode"] == "host" else c["id"][:12])
        e.setdefault("HOME", "/root")
        if len(cmd) > 1 and base == "printenv":
            for k in cmd[1:]:
                if k in e:
                    out(e[k])
            return 0 if all(k in e for k in cmd[1:]) else 1
        for k, v in e.items():
            out("%s=%s" % (k, v))
        return 0
    if base == "hostname":
        out(HOST if c["netmode"] == "host" else c["id"][:12])
        return 0
    if base == "ls" and any(a.startswith("/dev") for a in cmd[1:]):
        devs = ["console", "core", "fd", "full", "mqueue", "null", "ptmx", "pts",
                "random", "shm", "stderr", "stdin", "stdout", "tty", "urandom", "zero"]
        if vis:
            devs += ["nvidia-modeset", "nvidia-uvm", "nvidia-uvm-tools", "nvidia0",
                     "nvidiactl"]
        out("  ".join(sorted(devs)))
        return 0
    if base in ("python3", "python") and c["kind"] == "vehiclecount":
        src = " ".join(cmd[1:])
        if "cuda.is_available" in src:
            if not comp:
                sys.stderr.write(
                    "/usr/local/lib/python3.10/dist-packages/torch/cuda/__init__.py:128: "
                    "UserWarning: CUDA initialization: Found no NVIDIA driver on your "
                    "system. Please check that you have an NVIDIA GPU and installed a "
                    "driver from http://www.nvidia.com/Download/index.aspx (Triggered "
                    "internally at ../c10/cuda/CUDAFunctions.cpp:108.)\n"
                    "  return torch._C._cuda_getDeviceCount() > 0\n")
            out("True" if comp else "False")
            return 0
        if "device_count" in src:
            out("1" if comp else "0")
            return 0
        if "--version" in cmd or "-V" in cmd:
            out("Python 3.10.12")
            return 0
    if base == "cat" and len(cmd) > 1 and cmd[1] == "/etc/os-release":
        out('PRETTY_NAME="Ubuntu 22.04.4 LTS"\nNAME="Ubuntu"\nVERSION_ID="22.04"')
        return 0
    if base in ("bash", "sh"):
        if len(cmd) > 2 and cmd[1] == "-c":
            return run_in(c, shlex.split(cmd[2]))
        raise DErr("(drill mock) an interactive shell inside the container is not "
                   "simulated. Run single commands instead, e.g.\n"
                   "  docker exec %s nvidia-smi\n  docker exec %s env\n"
                   "  docker exec %s ls /dev" % ((c["name"],) * 3), 1)
    if base in ("true", "echo"):
        out(" ".join(cmd[1:]))
        return 0
    raise notfound


GPUS_RE = re.compile(r'^"?(all|\d+|count=(all|\d+)|device=([\w,-]+))"?$')


def parse_gpus(v):
    m = GPUS_RE.match(v.strip("'"))
    if not m:
        raise DErr('invalid argument "%s" for "--gpus" flag: unexpected key \'%s\' in \'%s\''
                   '\nSee \'docker run --help\'.' % (v, v.split("=")[0], v), 125)
    g = m.group(1)
    if g == "all" or m.group(2) == "all":
        return {"Driver": "", "Count": -1, "DeviceIDs": None, "Capabilities": [["gpu"]],
                "Options": {}}
    if m.group(3):
        return {"Driver": "", "Count": 0, "DeviceIDs": m.group(3).split(","),
                "Capabilities": [["gpu"]], "Options": {}}
    n = int(m.group(2) or g)
    return {"Driver": "", "Count": n, "DeviceIDs": None, "Capabilities": [["gpu"]],
            "Options": {}}


RUN_SPEC = {"-d|--detach": False, "--name": True, "--gpus": True, "--runtime": True,
            "-e|--env": True, "--env-file": True, "--restart": True, "-v|--volume": True,
            "--network|--net": True, "--rm": False, "-i|--interactive": False,
            "-t|--tty": False, "--privileged": False, "--ipc": True, "--shm-size": True,
            "-p|--publish": True, "--device": True, "-w|--workdir": True,
            "--entrypoint": True, "-l|--label": True, "-u|--user": True,
            "--pull": True, "--init": False, "-h|--hostname": True,
            "--log-driver": True, "--log-opt": True}


def split_run_args(args):
    """flags before the image, command after it (docker stops flag parsing there)"""
    i = 0
    takes = set()
    for k, v in RUN_SPEC.items():
        if v:
            takes.update(k.split("|"))
    while i < len(args):
        a = args[i]
        if not a.startswith("-") or a == "-":
            break
        if a in takes:
            i += 1
        elif a.startswith("-") and not a.startswith("--") and len(a) > 2:
            # combined short flags, the last may take a value (-it, -dp 80:80)
            if ("-" + a[-1]) in takes:
                i += 1
        i += 1
    return args[:i], args[i:]


def cmd_run(args):
    flags, rest = split_run_args(args)
    o, _ = getopts(flags, RUN_SPEC, "docker run")
    if not rest:
        raise DErr('"docker run" requires at least 1 argument.\nSee \'docker run --help\'.'
                   '\n\nUsage:  docker run [OPTIONS] IMAGE [COMMAND] [ARG...]\n\nCreate and '
                   'run a new container from an image', 125)
    need_daemon("containers/create", "Post")
    ensure_root_state()
    image, cmd = rest[0], rest[1:]
    ref = image if ":" in image.split("/")[-1] else image + ":latest"
    if ref not in catalogue() and pullable(ref):
        sys.stderr.write("Unable to find image '%s' locally\n" % ref)
        with locked():
            st = load_state()
            try:
                pull_image(st, ref)
            except DErr as e:
                raise DErr("docker: " + e.msg + ".\nSee 'docker run --help'.", 125)
            save_state(st)
    if ref not in catalogue():
        host = image.split("/")[0] if "." in image.split("/")[0] else "registry-1.docker.io"
        sys.stderr.write("Unable to find image '%s' locally\n" % ref)
        raise DErr('docker: Error response from daemon: Get "https://%s/v2/": dial tcp: '
                   'lookup %s: Temporary failure in name resolution.\n\nRun \'docker run '
                   '--help\' for more information' % (host, host), 125)
    img = IMAGES[ref]
    devreqs = [parse_gpus(g) for g in o.get("--gpus", [])] or None
    runtime = o.get("--runtime", ["runc"])[-1]
    env = list(img["env"])
    for e in o.get("-e|--env", []):
        k = e.split("=", 1)[0]
        env = [x for x in env if x.split("=", 1)[0] != k]
        if "=" in e:
            env.append(e)
        elif k in os.environ:
            env.append("%s=%s" % (k, os.environ[k]))
    for ef in o.get("--env-file", []):
        try:
            for ln in open(ef):
                ln = ln.strip()
                if ln and not ln.startswith("#"):
                    env.append(ln)
        except OSError:
            raise DErr("docker: open %s: no such file or directory.\nSee 'docker run "
                       "--help'." % ef, 125)
    rp = o.get("--restart", ["no"])[-1]
    if rp.split(":")[0] not in ("no", "always", "unless-stopped", "on-failure"):
        raise DErr('docker: Error response from daemon: invalid restart policy \'%s\'.\n'
                   'See \'docker run --help\'.' % rp, 125)
    binds = []
    for v in o.get("-v|--volume", []):
        if not v.startswith("/"):
            raise DErr('docker: Error response from daemon: create %s: "%s" includes '
                       'invalid characters for a local volume name.\nSee \'docker run '
                       '--help\'.' % (v.split(":")[0], v.split(":")[0]), 125)
        binds.append(v)
    labels = {}
    for lb in o.get("-l|--label", []):
        k, _, v = lb.partition("=")
        labels[k] = v
    with locked():
        st = load_state()
        reconcile(st)
        name = o.get("--name", [None])[-1]
        if name:
            if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_.-]+", name):
                raise DErr('docker: Error response from daemon: Invalid container name '
                           '(%s), only [a-zA-Z0-9][a-zA-Z0-9_.-] are allowed.\nSee \'docker '
                           'run --help\'.' % name, 125)
            other = lookup(st, name)
            if other and other["name"] == name:
                raise DErr('docker: Error response from daemon: Conflict. The container name '
                           '"/%s" is already in use by container "%s". You have to remove '
                           '(or rename) that container to be able to reuse that name.\n\n'
                           'Run \'docker run --help\' for more information'
                           % (name, other["id"]), 125)
        else:
            name = "%s_%s" % (["eager", "vibrant", "quirky", "brave"][os.getpid() % 4],
                              ["turing", "hopper", "lovelace", "curie"][os.getpid() // 4 % 4])
        vis, comp, err = gpu_from_requests(devreqs, runtime)
        if err:
            raise DErr("docker: " + err + "\n\nRun 'docker run --help' for more "
                       "information", 125 if "runtime" in err or "select" in err else 127)
        if o.get("--device") and not devreqs:
            pass                                # raw /dev/nvidia* nodes: no driver libs, no CUDA
        lcfg = None
        if o.get("--log-driver") or o.get("--log-opt"):
            dl = daemon_logcfg()
            drv = o.get("--log-driver", [dl["Type"]])[-1]
            lcfg = {"Type": drv, "Config": dict(x.split("=", 1) for x in
                                                 o.get("--log-opt", []) if "=" in x)
                    if o.get("--log-opt") else ({} if o.get("--log-driver") else dl["Config"])}
            for k, v in lcfg["Config"].items():
                if k == "max-size":
                    try:
                        parse_size(v)
                    except ValueError as e:
                        raise DErr("docker: Error response from daemon: %s.\nSee 'docker "
                                   "run --help'." % e, 125)
        c = make_container(st, name, ref, env, cmd or img["cmd"], labels, rp,
                           o.get("--network|--net", ["bridge"])[-1], binds, runtime,
                           devreqs, workdir=o.get("-w|--workdir", [None])[-1],
                           logcfg=lcfg)
        if not has_workload(img["kind"]) or (cmd and cmd != img["cmd"] and
                                             cmd[:3] != ["python3", "-m", img["kind"]]):
            # one-shot command in a container: run it, record the exit, done
            c.update(status="running", started=time.time())
            save_state(st)
            try:
                rc = run_in(c, cmd or ["bash"]) if cmd else 0
            except DErr as e:
                msg = e.msg.replace("OCI runtime exec failed: exec failed",
                                    "failed to create task for container: failed to "
                                    "create shim task: OCI runtime create failed: runc "
                                    "create failed")
                sys.stderr.write("docker: Error response from daemon: %s.\n" % msg)
                rc = 127 if e.code == 126 else e.code
                c.update(status="created", exit_code=rc)
                if "--rm" in o:
                    remove(st, c)
                save_state(st)
                return rc
            c.update(status="exited", exit_code=rc, finished=time.time())
            if "--rm" in o:
                remove(st, c)
            save_state(st)
            return rc
        spawn(c)
        _seed_restarts(c)
        c["autoremove"] = "--rm" in o
        save_state(st)
    if "-d|--detach" in o:
        out(c["id"])
        return 0
    for r in read_log(c):
        emit(r, False)
    rc = follow([c], False)
    if rc == 130:
        with locked():
            st = load_state()
            c2 = lookup(st, c["id"])
            if c2:
                stop(c2)
                if c2.get("autoremove"):
                    remove(st, c2)
            save_state(st)
    return rc


# ------------------------------------------------------------------ compose
def compose_labels(proj, sname, h):
    img = proj.services[sname]["image"]
    ref = img if ":" in img.split("/")[-1] else img + ":latest"
    deps = ",".join("%s:%s:%s" % (d, (v or {}).get("condition", "service_started"), "false")
                    for d, v in (proj.services[sname].get("depends_on") or {}).items())
    return {
        "com.docker.compose.config-hash": h,
        "com.docker.compose.container-number": "1",
        "com.docker.compose.depends_on": deps,
        "com.docker.compose.image": "sha256:" + IMAGES.get(ref, {"id": "0" * 64})["id"],
        "com.docker.compose.oneoff": "False",
        "com.docker.compose.project": proj.name,
        "com.docker.compose.project.config_files": proj.path,
        "com.docker.compose.project.working_dir": proj.dir,
        "com.docker.compose.service": sname,
        "com.docker.compose.version": COMPOSE_V.lstrip("v"),
    }


def compose_create(st, proj, sname, created=None):
    s = proj.services[sname]
    img = s["image"]
    ref = img if ":" in img.split("/")[-1] else img + ":latest"
    if ref not in catalogue(st) and pullable(ref):
        pull_image(st, ref)
    if ref not in catalogue(st):
        host = img.split("/")[0] if "." in img.split("/")[0] else "registry-1.docker.io"
        raise DErr("Error response from daemon: Get \"https://%s/v2/\": dial tcp: lookup "
                   "%s: Temporary failure in name resolution" % (host, host))
    im = IMAGES[ref]
    env = [e for e in im["env"] if e.split("=", 1)[0] not in s["environment"]]
    for k, v in s["environment"].items():
        if v is not None:
            env.append("%s=%s" % (k, v))
        elif k in os.environ:
            env.append("%s=%s" % (k, os.environ[k]))
    binds = []
    for v in s.get("volumes") or []:
        if isinstance(v, dict) and v.get("type") == "bind":
            binds.append("%s:%s%s" % (v["source"], v["target"],
                                      ":ro" if v.get("read_only") else ":rw"))
    devreqs, runtime = service_gpu(s)
    _, _, err = gpu_from_requests(devreqs, runtime)
    if err:
        raise DErr(err)
    cmd = s.get("command")
    if isinstance(cmd, str):
        cmd = shlex.split(cmd)
    lcfg = None
    lg = s.get("logging")
    if isinstance(lg, dict) and (lg.get("driver") or lg.get("options")):
        dl = daemon_logcfg()
        opts = {str(k): str(v) for k, v in (lg.get("options") or {}).items()}
        lcfg = {"Type": str(lg.get("driver") or dl["Type"]),
                "Config": opts if lg.get("options") is not None or lg.get("driver")
                else dl["Config"]}
        if "max-size" in opts:
            try:
                parse_size(opts["max-size"])
            except ValueError as e:
                raise DErr("Error response from daemon: %s" % e)
    return make_container(st, proj.cname(sname), ref, env, cmd or im["cmd"],
                          compose_labels(proj, sname, proj.svc_hash(sname)),
                          s.get("restart") or "no", s.get("network_mode") or
                          "%s_default" % proj.name, binds, runtime, devreqs, created,
                          logcfg=lcfg)


class Progress:
    """compose's progress output: the [+] block on a tty, plain events otherwise"""
    def __init__(self, verb):
        self.verb, self.rows, self.tty = verb, [], sys.stderr.isatty()

    def event(self, name, text, final=False, t=0.0, err=False):
        if not self.tty:
            sys.stderr.write(" Container %s  %s\n" % (name, text))
        if final:
            self.rows.append((name, text, t, err))

    def done(self):
        if not self.tty or not self.rows:
            return
        n = len(self.rows)
        ok = sum(1 for r in self.rows if not r[3])
        sys.stderr.write("[+] %s %d/%d\n" % (self.verb, ok, n))
        w = max(len(r[0]) for r in self.rows)
        for name, text, t, err in self.rows:
            left = " %s Container %s  %s" % ("✘" if err else "✔", name.ljust(w), text)
            sys.stderr.write("%s%s\n" % (left.ljust(66), ("%.1fs" % t).rjust(6)))


def project_containers(st, pname):
    return [c for c in st["containers"].values()
            if (c["labels"] or {}).get("com.docker.compose.project") == pname]


def compose_main(args):
    files, pname, pdir, i = [], None, None, 0
    while i < len(args) and args[i].startswith("-"):
        a = args[i]
        if a in ("-f", "--file"):
            files.append(args[i + 1]); i += 2
        elif a.startswith("--file="):
            files.append(a.split("=", 1)[1]); i += 1
        elif a in ("-p", "--project-name"):
            pname = args[i + 1]; i += 2
        elif a in ("--project-directory",):
            pdir = args[i + 1]; i += 2
        elif a in ("-v", "--version"):
            out("Docker Compose version " + COMPOSE_V); return 0
        elif a in ("-h", "--help"):
            i = len(args); args = args + ["help"]; break
        elif a in ("--ansi", "--progress", "--env-file", "--profile"):
            i += 2
        else:
            raise DErr("unknown flag: %s" % a)
    sub, rest = (args[i], args[i + 1:]) if i < len(args) else ("help", [])
    if sub in ("help",):
        out("Usage:  docker compose [OPTIONS] COMMAND\n\nDefine and run multi-container "
            "applications with Docker\n\nOptions:\n  -f, --file stringArray     Compose "
            "configuration files\n  -p, --project-name string  Project name\n\nCommands:\n"
            "  config      Parse, resolve and render compose file in canonical format\n"
            "  down        Stop and remove containers, networks\n"
            "  logs        View output from containers\n"
            "  ls          List running compose projects\n"
            "  ps          List containers\n"
            "  restart     Restart service containers\n"
            "  start       Start services\n"
            "  stop        Stop services\n"
            "  up          Create and start containers\n"
            "  version     Show the Docker Compose version information")
        return 0
    if sub == "version":
        out("Docker Compose version " + COMPOSE_V)
        return 0
    known = {"up", "down", "ps", "logs", "restart", "stop", "start", "config", "ls",
             "top", "images", "exec", "pull", "create", "rm", "kill"}
    if sub not in known:
        raise DErr('unknown docker command: "compose %s"' % sub)
    need_daemon("containers/json?all=1&filters=%7B%22label%22%3A%7B%22com.docker.compose"
                ".config-hash%22%3Atrue%7D%7D", "Get") if sub not in ("config",) else None

    if sub == "ls":
        st = load_state()
        reconcile(st)
        projs = {}
        for c in st["containers"].values():
            lab = c["labels"] or {}
            if "com.docker.compose.project" in lab:
                p = projs.setdefault(lab["com.docker.compose.project"],
                                     [lab.get("com.docker.compose.project.config_files", ""),
                                      0, 0])
                p[1 if c["status"] == "running" else 2] += 1
        rows = [["NAME", "STATUS", "CONFIG FILES"]]
        for n, (f, r, e) in sorted(projs.items()):
            s = ", ".join(x for x in (("running(%d)" % r) if r else "",
                                      ("exited(%d)" % e) if e else "") if x)
            if r or "-a" in rest or "--all" in rest:
                rows.append([n, s, f])
        table(rows)
        return 0

    # which project: a file, or -p NAME on its own for the read-only verbs
    proj = None
    try:
        proj = Project(find_compose_file(files, pdir), pname)
        for w in proj.warnings:
            sys.stderr.write(w + "\n")
        pname = proj.name
    except DErr:
        if not (pname and not files and sub in ("ps", "logs", "restart", "stop", "start",
                                                "down", "top")):
            raise

    if sub == "config":
        o, p = getopts(rest, {"--services": False, "-q|--quiet": False,
                              "--hash": True, "--format": True}, "docker compose config")
        if "-q|--quiet" in o:
            return 0
        if "--services" in o:
            for s in proj.services:
                out(s)
            return 0
        if "--hash" in o:
            for s in proj.services:
                out("%s %s" % (s, proj.svc_hash(s)))
            return 0
        doc = {"name": proj.name, "services": {}}
        for s, v in proj.services.items():
            d = dict(v)
            if not d["network_mode"]:
                d.pop("network_mode")
                d["networks"] = {"default": None}
            doc["services"][s] = d
        out(yaml_dump(doc))
        return 0

    ensure_root_state() if sub in ("up", "down", "restart", "stop", "start", "rm",
                                   "create", "kill") else None

    with locked():
        st = load_state()
        reconcile(st)
        mine = project_containers(st, pname)
        by_svc = {(c["labels"] or {}).get("com.docker.compose.service"): c for c in mine}

        if sub == "ps":
            o, p = getopts(rest, {"-a|--all": False, "-q|--quiet": False, "--format": True,
                                  "--services": False, "--status": True},
                           "docker compose ps")
            cs = sorted(mine, key=lambda c: c["name"])
            if p:
                cs = [c for c in cs if c["labels"]["com.docker.compose.service"] in p]
            if "-a|--all" not in o:
                cs = [c for c in cs if c["status"] in ("running", "restarting")]
            if "-q|--quiet" in o:
                for c in cs:
                    out(c["id"])
                return 0
            if "--services" in o:
                for c in cs:
                    out(c["labels"]["com.docker.compose.service"])
                return 0
            ctx = [ps_ctx(c) for c in cs]
            if "--format" in o:
                fmt_rows(o["--format"][-1], ctx)
                return 0
            rows = [["NAME", "IMAGE", "COMMAND", "SERVICE", "CREATED", "STATUS", "PORTS"]]
            for x in ctx:
                rows.append([x["Names"], x["Image"], x["Command"], x["Service"],
                             x["RunningFor"], x["Status"], x["Ports"]])
            table(rows)
            return 0

        if sub == "logs":
            o, p = getopts(rest, {"-f|--follow": False, "-n|--tail": True,
                                  "-t|--timestamps": False, "--no-color": False,
                                  "--no-log-prefix": False, "--since": True},
                           "docker compose logs")
            cs = sorted(mine, key=lambda c: c["name"])
            if p:
                cs = [c for c in cs if c["labels"]["com.docker.compose.service"] in p]
            w = max([len(c["name"]) for c in cs] or [0])
            pre = {c["id"]: ("" if "--no-log-prefix" in o else c["name"].ljust(w) + "  | ")
                   for c in cs}
            tail = o.get("-n|--tail", ["all"])[-1]
            stamps = "-t|--timestamps" in o
            for c in cs:
                recs = list(read_log(c))
                if tail != "all":
                    recs = recs[-int(tail):] if int(tail) > 0 else []
                for r in recs:
                    emit(r, stamps, pre[c["id"]])
            if "-f|--follow" in o:
                return follow(cs, stamps, pre)
            return 0

        if sub == "pull":
            o, p = getopts(rest, {"-q|--quiet": False, "--ignore-pull-failures": False,
                                  "--include-deps": False, "--policy": True},
                           "docker compose pull")
            ensure_root_state()
            rc = 0
            for sname in proj.order(p or None):
                img = proj.services[sname]["image"]
                ref = img if ":" in img.split("/")[-1] else img + ":latest"
                sys.stderr.write(" %s Pulling \n" % sname)
                if not pullable(ref):
                    host = img.split("/")[0] if "." in img.split("/")[0] else \
                        "registry-1.docker.io"
                    sys.stderr.write(" %s Error Get \"https://%s/v2/\": dial tcp: lookup "
                                     "%s: Temporary failure in name resolution\n"
                                     % (sname, host, host))
                    rc = 18
                    continue
                try:
                    pull_image(st, ref)
                    save_state(st)
                    sys.stderr.write(" %s Pulled \n" % sname)
                except DErr as e:
                    sys.stderr.write(" %s Error %s\n" % (sname, e.msg))
                    sys.stderr.write("Error response from daemon: %s\n" % e.msg)
                    return 18
            return rc

        if sub == "top":
            for c in mine:
                out(c["name"])
                cmd_top([c["id"]])
                out("")
            return 0

        if sub in ("restart", "stop", "start", "kill"):
            o, p = getopts(rest, {"-t|--timeout": True, "-s|--signal": True,
                                  "--no-deps": False}, "docker compose " + sub)
            order = proj.order(p or None) if proj else \
                sorted(by_svc, key=lambda s: by_svc[s]["created"])
            if sub in ("stop", "kill"):
                order = list(reversed(order))
            pg = Progress({"restart": "Restarting", "stop": "Stopping",
                           "start": "Running", "kill": "Killing"}[sub])
            for s in order:
                c = by_svc.get(s)
                if not c:
                    continue
                t0 = time.time()
                c["manual_stop"] = sub in ("stop", "kill")
                if sub in ("restart", "stop", "kill"):
                    pg.event(c["name"], {"restart": "Restarting", "stop": "Stopping",
                                         "kill": "Killing"}[sub])
                    stop(c, 0 if sub == "kill" else int(o.get("-t|--timeout", [10])[-1]))
                if sub in ("restart", "start"):
                    if c["status"] != "running":
                        pg.event(c["name"], "Starting")
                        spawn(c)
                    pg.event(c["name"], "Started", True, time.time() - t0)
                else:
                    pg.event(c["name"], "Stopped" if sub == "stop" else "Killed", True,
                             time.time() - t0)
            save_state(st)
            pg.done()
            return 0

        if sub in ("down", "rm"):
            o, p = getopts(rest, {"-v|--volumes": False, "--remove-orphans": False,
                                  "-t|--timeout": True, "--rmi": True, "-f|--force": False,
                                  "-s|--stop": False}, "docker compose " + sub)
            pg = Progress("Running")
            for c in sorted(mine, key=lambda c: -c["created"]):
                if sub == "rm" and c["status"] == "running" and "-s|--stop" not in o:
                    continue
                t0 = time.time()
                pg.event(c["name"], "Stopping")
                stop(c)
                pg.event(c["name"], "Stopped")
                pg.event(c["name"], "Removing")
                remove(st, c)
                pg.event(c["name"], "Removed", True, time.time() - t0)
            save_state(st)
            pg.done()
            return 0

        if sub in ("up", "create"):
            o, p = getopts(rest, {"-d|--detach": False, "--force-recreate": False,
                                  "--no-recreate": False, "--remove-orphans": False,
                                  "--wait": False, "--pull": True, "--build": False,
                                  "--no-deps": False, "--no-start": False,
                                  "-t|--timeout": True, "--quiet-pull": False},
                           "docker compose " + sub)
            order = proj.order(p or None)
            orphans = [c for s, c in by_svc.items() if s not in proj.services]
            if orphans and "--remove-orphans" not in o:
                sys.stderr.write(
                    "WARN[0000] Found orphan containers ([%s]) for this project. If you "
                    "removed or renamed this service in your compose file, you can run this "
                    "command with the --remove-orphans flag to clean it up. \n"
                    % " ".join(c["name"] for c in orphans))
            back = dict(x.split("=", 1) for x in
                        os.environ.get("MOCK_DOCKER_BACKDATE", "").split(",") if "=" in x)
            pg = Progress("Running")
            started = []
            for s in order:
                h = proj.svc_hash(s)
                cname = proj.cname(s)
                c = by_svc.get(s)
                t0 = time.time()
                other = lookup(st, cname)
                if other and other["name"] == cname and other is not c:
                    raise DErr('Error response from daemon: Conflict. The container name '
                               '"/%s" is already in use by container "%s". You have to '
                               'remove (or rename) that container to be able to reuse that '
                               'name.' % (cname, other["id"]))
                if c and ((c["labels"] or {}).get("com.docker.compose.config-hash") != h
                          or "--force-recreate" in o) and "--no-recreate" not in o:
                    pg.event(cname, "Recreate")
                    remove(st, c)
                    c = compose_create(st, proj, s)
                    pg.event(cname, "Recreated")
                    if sub == "create":
                        pg.event(cname, "Created", True, time.time() - t0)
                        continue
                    pg.event(cname, "Starting")
                    spawn(c)
                    pg.event(cname, "Started", True, time.time() - t0,
                             c["status"] != "running")
                elif c:
                    if c["status"] != "running" and sub == "up":
                        pg.event(cname, "Starting")
                        c["manual_stop"] = False
                        spawn(c)
                        pg.event(cname, "Started", True, time.time() - t0)
                    else:
                        pg.event(cname, "Running", True, 0.0)
                else:
                    pg.event(cname, "Creating")
                    bd = int(back[s]) if s in back else None
                    c = compose_create(st, proj, s, created=(time.time() - bd) if bd else None)
                    pg.event(cname, "Created")
                    if sub == "create":
                        pg.rows.append((cname, "Created", time.time() - t0, False))
                        continue
                    pg.event(cname, "Starting")
                    spawn(c, backdate=c["created"] if bd else None)
                    _seed_restarts(c)
                    if bd and c["status"] == "running":
                        c["started"] = c["created"] + 7
                    pg.event(cname, "Started", True, time.time() - t0,
                             c["status"] != "running")
                started.append(c)
                save_state(st)
            if "--remove-orphans" in o:
                for c in orphans:
                    pg.event(c["name"], "Removed", True, 0.0)
                    remove(st, c)
            save_state(st)
            pg.done()
        # attached `up`: stream logs until Ctrl-C, then stop (the real behaviour)
    if sub == "up" and "-d|--detach" not in o:
        w = max(len(c["name"]) for c in started)
        pre = {c["id"]: c["name"].ljust(w) + "  | " for c in started}
        out("Attaching to " + ", ".join(c["name"] for c in started))
        rc = follow(started, False, pre)
        if rc == 130:
            sys.stderr.write("Gracefully stopping... (press Ctrl+C again to force)\n")
            with locked():
                st = load_state()
                pg = Progress("Stopping")
                for c in reversed(started):
                    c2 = lookup(st, c["id"])
                    if c2:
                        stop(c2)
                        pg.event(c2["name"], "Stopped", True, 0.4)
                save_state(st)
                pg.done()
        return rc
    return 0


# ------------------------------------------------------------------ images: rm / prune / df
def _confirm(msg):
    sys.stdout.write(msg + "\nAre you sure you want to continue? [y/N] ")
    sys.stdout.flush()
    return sys.stdin.readline().strip().lower() in ("y", "yes")


def _in_use(st):
    return {c["image"] for c in st["containers"].values()}


def _drop_images(st, refs):
    """-> printed lines + bytes freed"""
    gone = st.setdefault("removed_images", [])
    lines, freed = [], 0
    import shutil
    for ref in refs:
        img = IMAGES[ref]
        gone.append(ref)
        if ref in (st.get("pulled_images") or []):
            st["pulled_images"].remove(ref)
        freed += img_bytes(img)
        shutil.rmtree(layer_dir(img), ignore_errors=True)
        if not img.get("dangling"):
            lines += ["untagged: %s" % ref,
                      "untagged: %s@sha256:%s" % (ref.rsplit(":", 1)[0], hashlib.sha256(
                          img["id"].encode()).hexdigest())]
        lines += ["deleted: sha256:%s" % img["id"]]
        for i in range(3):
            lines.append("deleted: sha256:%s" % hashlib.sha256(
                ("%s/%d" % (img["id"], i)).encode()).hexdigest())
    return lines, freed


def cmd_rmi(args):
    o, p = getopts(args, {"-f|--force": False, "--no-prune": False}, "docker rmi")
    if not p:
        raise DErr('"docker rmi" requires at least 1 argument.')
    need_daemon("images/%s" % p[0], "Delete")
    ensure_root_state()
    rc = 0
    with locked():
        st = load_state()
        reconcile(st)
        cat = catalogue(st)
        for ref in p:
            r = ref if ref in cat else ref + ":latest" if ref + ":latest" in cat else \
                next((k for k, v in cat.items() if v["id"].startswith(ref)), None)
            if not r:
                sys.stderr.write("Error response from daemon: No such image: %s\n" % ref)
                rc = 1
                continue
            users = [c for c in st["containers"].values() if c["image"] == r]
            if users and "-f|--force" not in o:
                c = users[0]
                sys.stderr.write(
                    "Error response from daemon: conflict: unable to remove repository "
                    "reference \"%s\" (must force) - container %s is using its referenced "
                    "image %s\n" % (ref, c["id"][:12], IMAGES[r]["id"][:12]))
                rc = 1
                continue
            lines, _ = _drop_images(st, [r])
            for ln in lines:
                out(ln[0].upper() + ln[1:])
        save_state(st)
    return rc


def cmd_image_prune(args):
    o, p = getopts(args, {"-a|--all": False, "-f|--force": False, "--filter": True},
                   "docker image prune")
    need_daemon("images/prune", "Post")
    ensure_root_state()
    allimg = "-a|--all" in o
    if "-f|--force" not in o and not _confirm(
            "WARNING! This will remove all images without at least one container "
            "associated to them." if allimg else "WARNING! This will remove all dangling images."):
        return 0
    with locked():
        st = load_state()
        reconcile(st)
        used = _in_use(st)
        refs = [r for r, v in catalogue(st).items() if r not in used and
                (allimg or v.get("dangling"))]
        lines, freed = _drop_images(st, refs)
        save_state(st)
    if lines:
        out("Deleted Images:")
        for ln in lines:
            out(ln)
        out("")
    out("Total reclaimed space: %s" % _hsize(freed))
    return 0


def cmd_system(args):
    sub = args[0] if args else ""
    if sub == "df":
        o, p = getopts(args[1:], {"-v|--verbose": False, "--format": True}, "docker system df")
        need_daemon("system/df")
        st = load_state()
        reconcile(st)
        cat = catalogue(st)
        used = _in_use(st)
        tot = sum(img_bytes(v) for v in cat.values())
        rec = sum(img_bytes(v) for k, v in cat.items() if k not in used)
        cs = list(st["containers"].values())
        run = sum(1 for c in cs if c["status"] in ("running", "restarting"))
        pct = lambda a, b: " (%d%%)" % (a * 100 // b) if b else ""
        table([["TYPE", "TOTAL", "ACTIVE", "SIZE", "RECLAIMABLE"],
               ["Images", str(len(cat)), str(len([k for k in cat if k in used])),
                _hsize(tot), _hsize(rec) + pct(rec, tot)],
               ["Containers", str(len(cs)), str(run), "0B", "0B"],
               ["Local Volumes", "0", "0", "0B", "0B"],
               ["Build Cache", "0", "0", "0B", "0B"]])
        return 0
    if sub == "prune":
        o, p = getopts(args[1:], {"-a|--all": False, "-f|--force": False, "--volumes": False,
                                  "--filter": True}, "docker system prune")
        need_daemon("containers/prune", "Post")
        ensure_root_state()
        warn = ("WARNING! This will remove:\n  - all stopped containers\n  - all networks "
                "not used by at least one container\n  - %s\n  - unused build cache\n"
                % ("all images without at least one container associated to them"
                   if "-a|--all" in o else "all dangling images"))
        if "-f|--force" not in o and not _confirm(warn):
            return 0
        with locked():
            st = load_state()
            reconcile(st)
            dead = [c for c in st["containers"].values() if c["status"] in ("exited", "created")]
            for c in dead:
                remove(st, c)
            refs = [r for r, v in catalogue(st).items() if r not in _in_use(st) and
                    ("-a|--all" in o or v.get("dangling"))]
            lines, freed = _drop_images(st, refs)
            save_state(st)
        if dead:
            out("Deleted Containers:")
            for c in dead:
                out(c["id"])
            out("")
        if lines:
            out("Deleted Images:")
            for ln in lines:
                out(ln)
            out("")
        out("Total reclaimed space: %s" % _hsize(freed))
        return 0
    raise DErr("Usage:  docker system COMMAND\n\nManage Docker\n\nCommands:\n"
               "  df          Show docker disk usage\n  info        Display system-wide "
               "information\n  prune       Remove unused data")


def _pull_lines(ref, img):
    repo, _, tag = ref.rpartition(":")
    ls = [hashlib.sha256(("%s/%d" % (img["id"], i)).encode()).hexdigest()[:12]
          for i in range(3)]
    return ["%s: Pulling from %s" % (tag, repo.split("/", 1)[-1])] + \
        ["%s: Pulling fs layer" % x for x in ls] + \
        ["%s: Download complete" % x for x in ls], ls


def cmd_pull(args):
    o, p = getopts(args, {"-q|--quiet": False, "-a|--all-tags": False, "--platform": True},
                   "docker pull")
    if len(p) != 1:
        raise DErr('"docker pull" requires exactly 1 argument.\nSee \'docker pull --help\'.'
                   '\n\nUsage:  docker pull [OPTIONS] NAME[:TAG|@DIGEST]\n\nDownload an '
                   'image from a registry')
    need_daemon("images/create", "Post")
    ensure_root_state()
    image = p[0]
    ref = image if ":" in image.split("/")[-1] else image + ":latest"
    if not pullable(ref):
        host = image.split("/")[0] if "." in image.split("/")[0] else "registry-1.docker.io"
        raise DErr('Error response from daemon: Get "https://%s/v2/": dial tcp: lookup %s: '
                   'Temporary failure in name resolution' % (host, host))
    img = IMAGES[ref]
    q = "-q|--quiet" in o
    with locked():
        st = load_state()
        head, ls = _pull_lines(ref, img)
        if ref in catalogue(st) and (not img.get("disk") or
                                     os.path.isfile(os.path.join(layer_dir(img), "diff",
                                                                 "layer.tar"))):
            if not q:
                out("%s: Pulling from %s" % (ref.rpartition(":")[2],
                                              ref.rpartition(":")[0].split("/", 1)[-1]))
                out("Digest: sha256:%s" % hashlib.sha256(img["id"].encode()).hexdigest())
                out("Status: Image is up to date for %s" % ref)
            out(ref)
            return 0
        if not q:
            for ln in head:
                out(ln)
        try:
            pull_image(st, ref)
        except DErr as e:
            if not q:
                out("%s: Extracting" % ls[0])
            raise DErr(e.msg)
        save_state(st)
    if not q:
        for x in ls:
            out("%s: Pull complete" % x)
        out("Digest: sha256:%s" % hashlib.sha256(img["id"].encode()).hexdigest())
        out("Status: Downloaded newer image for %s" % ref)
    out(ref)
    return 0


# ------------------------------------------------------------------ top level
def cmd_version(args):
    out("Client: Docker Engine - Community\n Version:           %s\n API version:       %s\n"
        " Go version:        go1.22.7\n Git commit:        ce12230\n Built:             "
        "Fri Sep 20 11:41:00 2024\n OS/Arch:           linux/amd64\n Context:           "
        "default\n" % (VERSION, API))
    need_daemon("version")
    out("Server: Docker Engine - Community\n Engine:\n  Version:          %s\n  API version:"
        "      %s (minimum version 1.24)\n  Go version:       go1.22.7\n  Git commit:       "
        "41ca978\n  Built:            Fri Sep 20 11:41:00 2024\n  OS/Arch:          "
        "linux/amd64\n  Experimental:     false\n containerd:\n  Version:          1.7.22\n"
        "  GitCommit:        7f7fdf5fed64eb6a7caf99b3e12efcf9d60e311c\n runc:\n  Version:"
        "          1.1.14\n  GitCommit:        v1.1.14-0-g2c9f560\n docker-init:\n  Version:"
        "          0.19.0\n  GitCommit:        de40ad0" % (VERSION, API))
    return 0


def cmd_info(args):
    out("Client: Docker Engine - Community\n Version:    %s\n Context:    default\n Debug "
        "Mode: false\n Plugins:\n  buildx: Docker Buildx (Docker Inc.)\n    Version:  "
        "v0.17.1\n    Path:     /usr/libexec/docker/cli-plugins/docker-buildx\n  compose: "
        "Docker Compose (Docker Inc.)\n    Version:  %s\n    Path:     "
        "/usr/libexec/docker/cli-plugins/docker-compose\n" % (VERSION, COMPOSE_V))
    need_daemon("info")
    st = load_state()
    reconcile(st)
    cs = list(st["containers"].values())
    run = sum(1 for c in cs if c["status"] == "running")
    rts = ["io.containerd.runc.v2", "runc"]
    try:
        with open("/etc/docker/daemon.json") as f:
            dj = json.load(f)
        rts += list((dj.get("runtimes") or {}).keys())
        default_rt = dj.get("default-runtime", "runc")
    except (OSError, ValueError):
        default_rt = "runc"
    mem = 0
    with open("/proc/meminfo") as f:
        mem = int(f.readline().split()[1]) / 1024.0 / 1024.0
    out("Server:\n Containers: %d\n  Running: %d\n  Paused: 0\n  Stopped: %d\n Images: %d\n"
        " Server Version: %s\n Storage Driver: overlay2\n  Backing Filesystem: extfs\n"
        " Logging Driver: json-file\n Cgroup Driver: systemd\n Cgroup Version: 2\n Plugins:\n"
        "  Volume: local\n  Network: bridge host ipvlan macvlan null overlay\n"
        "  Log: awslogs fluentd gcplogs gelf journald json-file local splunk syslog\n"
        " Swarm: inactive\n Runtimes: %s\n Default Runtime: %s\n Init Binary: docker-init\n"
        " Kernel Version: %s\n Operating System: Debian GNU/Linux 12 (bookworm)\n"
        " OSType: linux\n Architecture: x86_64\n CPUs: %d\n Total Memory: %.2fGiB\n"
        " Name: %s\n Docker Root Dir: /var/lib/docker\n Debug Mode: false\n"
        " Live Restore Enabled: false"
        % (len(cs), run, len(cs) - run, len(catalogue(st)), VERSION, " ".join(sorted(set(rts))),
           default_rt, os.uname().release, os.cpu_count() or 1, mem, HOST))
    return 0


USAGE = """
Usage:  docker [OPTIONS] COMMAND

A self-sufficient runtime for containers

Common Commands:
  run         Create and run a new container from an image
  exec        Execute a command in a running container
  ps          List containers
  images      List images
  pull        Download an image from a registry
  system      Manage Docker (df, prune)
  version     Show the Docker version information
  info        Display system-wide information

Management Commands:
  compose*    Docker Compose (Docker Inc.)
  container   Manage containers
  image       Manage images

Commands:
  inspect     Return low-level information on Docker objects
  logs        Fetch the logs of a container
  restart     Restart one or more containers
  rm          Remove one or more containers
  rmi         Remove one or more images
  start       Start one or more stopped containers
  stats       Display a live stream of container(s) resource usage statistics
  stop        Stop one or more running containers
  top         Display the running processes of a container

Run 'docker COMMAND --help' for more information on a command.
"""

CMDS = {"ps": cmd_ps, "images": cmd_images, "inspect": cmd_inspect, "logs": cmd_logs,
        "restart": cmd_restart, "stop": cmd_stop, "start": cmd_start, "rm": cmd_rm,
        "run": cmd_run, "exec": cmd_exec, "top": cmd_top, "stats": cmd_stats,
        "version": cmd_version, "info": cmd_info, "rmi": cmd_rmi, "system": cmd_system,
        "image prune": cmd_image_prune, "pull": cmd_pull}
ALIASES = {("container", "ls"): "ps", ("container", "list"): "ps",
           ("container", "inspect"): "inspect", ("container", "logs"): "logs",
           ("container", "restart"): "restart", ("container", "stop"): "stop",
           ("container", "start"): "start", ("container", "rm"): "rm",
           ("container", "run"): "run", ("container", "exec"): "exec",
           ("container", "top"): "top", ("container", "stats"): "stats",
           ("image", "ls"): "images", ("image", "list"): "images",
           ("image", "inspect"): "inspect", ("image", "rm"): "rmi",
           ("image", "prune"): "image prune", ("image", "pull"): "pull",
           ("system", "info"): "info"}


def main(argv):
    a = list(argv)
    while a and a[0] in ("-D", "--debug", "-l", "--log-level", "--context", "-c", "-H",
                         "--host"):
        a = a[2:] if a[0] in ("-l", "--log-level", "--context", "-c", "-H", "--host") else a[1:]
    if not a or a[0] in ("-h", "--help", "help"):
        sys.stdout.write(USAGE)
        return 0
    if a[0] in ("-v", "--version"):
        out("Docker version %s, build ce12230" % VERSION)
        return 0
    if a[0] == "compose":
        return compose_main(a[1:])
    if len(a) > 1 and (a[0], a[1]) in ALIASES:
        a = [ALIASES[(a[0], a[1])]] + a[2:]
    elif a[0] in ("container", "image"):
        raise DErr("docker: '%s %s' is not a docker command.\nSee 'docker --help'"
                   % (a[0], a[1] if len(a) > 1 else ""))
    if a[0] == "ls":
        a[0] = "ps"
    if a[0] not in CMDS:
        raise DErr("docker: '%s' is not a docker command.\nSee 'docker --help'" % a[0])
    if "--help" in a[1:] or "-h" in a[1:] and a[0] != "run":
        out("Usage:  docker %s [OPTIONS] ...\n\n(see 'docker --help')" % a[0])
        return 0
    return CMDS[a[0]](a[1:])


if __name__ == "__main__":
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    try:
        sys.exit(main(sys.argv[1:]) or 0)
    except DErr as e:
        sys.stdout.flush()
        sys.stderr.write(e.msg + "\n")
        sys.exit(e.code)
    except KeyboardInterrupt:
        sys.exit(130)

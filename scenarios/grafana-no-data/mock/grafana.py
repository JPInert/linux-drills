# drill mock: grafana/grafana 11.2 (host network, :3000). Reads its datasource
# provisioning at START (like the real one), runs the dashboard's panel query
# every 10 s against that datasource for real, and answers enough of the HTTP
# API for curl: /api/health, /api/datasources, /api/datasources/uid/X/health,
# /api/datasources/proxy/uid/X/<prometheus api>, /api/ds/query.
import base64, hashlib, json, os, re, signal, socket, sys, threading, time
import urllib.error, urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from mdcommon import procname, write, host_path

VER, COMMIT = "11.2.0", "2a88694fd3ced0335bf3726cc5d0adc2d1858855"
STATE = "/run/.drill-grafana-state"
PROV = os.environ.get("GF_PATHS_PROVISIONING", "/etc/grafana/provisioning")
USER = os.environ.get("GF_SECURITY_ADMIN_USER", "admin")
PASS = os.environ.get("GF_SECURITY_ADMIN_PASSWORD", "admin")
DS = []


def ts(t=None):
    t = t or time.time()
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%06dZ" % int((t % 1) * 1e6)


def lg(logger, level, msg, extra="", pre="", t=None):
    t = time.time() if t is None else t
    write("logger=%s %st=%s level=%s msg=%s%s" % (
        logger, (pre + " ") if pre else "", ts(t), level,
        ('"%s"' % msg) if " " in msg else msg, (" " + extra) if extra else ""), t)


# ---------------------------------------------------------------- provisioning
def _val(v):
    v = v.split(" #")[0].strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
        v = v[1:-1]
    if v in ("true", "false"):
        return v == "true"
    return v


def parse_ds(text, fname):
    """datasources: - name: ... (scalar keys; nested maps are skipped)"""
    out, cur, in_ds, item_ind, nest = [], None, False, None, None
    for n, raw in enumerate(text.splitlines(), 1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if "\t" in raw[:len(raw) - len(raw.lstrip())]:
            raise ValueError("yaml: line %d: found character that cannot start any token"
                             % n)
        ind = len(raw) - len(raw.lstrip())
        s = raw.strip()
        if ind == 0:
            in_ds = s.startswith("datasources:")
            cur = None
            continue
        if not in_ds:
            continue
        if s.startswith("- "):
            item_ind = ind + 2
            cur = {}
            out.append(cur)
            s = s[2:].strip()
            ind = item_ind
            nest = None
        if cur is None:
            continue
        if nest is not None and ind > nest:
            continue
        nest = None
        k, sep, v = s.partition(":")
        if not sep:
            raise ValueError("yaml: line %d: could not find expected ':'" % n)
        if v.strip() == "":
            nest = ind
            continue
        cur[k.strip()] = _val(v)
    return out


def provision():
    d = PROV.rstrip("/") + "/datasources"
    hd = host_path(d) or d
    res = []
    try:
        names = sorted(os.listdir(hd))
    except OSError:
        names = []
    for f in names:
        if not f.endswith((".yaml", ".yml")):
            continue
        try:
            text = open(os.path.join(hd, f)).read()
        except OSError:
            continue
        try:
            items = parse_ds(text, f)
        except ValueError as e:
            lg("provisioning", "error", "Failed to provision data sources",
               'error="Datasource provisioning error: %s/%s: %s"' % (d, f, e))
            sys.exit(1)
        for it in items:
            if not it.get("name"):
                continue
            it.setdefault("uid", "P" + hashlib.sha1(it["name"].encode()).hexdigest()[:15]
                          .upper())
            it.setdefault("access", "proxy")
            it["file"] = "%s/%s" % (d, f)
            res.append(it)
    return res


# ---------------------------------------------------------------- queries
def goerr(url, e):
    u = urllib.parse.urlparse(url)
    host = u.hostname or ""
    port = u.port or (443 if u.scheme == "https" else 80)
    r = getattr(e, "reason", e)
    if isinstance(r, socket.gaierror):
        ns = "127.0.0.11"
        try:
            for ln in open("/etc/resolv.conf"):
                if ln.startswith("nameserver"):
                    ns = ln.split()[1]
                    break
        except OSError:
            pass
        return 'Post "%s": dial tcp: lookup %s on %s:53: no such host' % (url, host, ns)
    try:
        ip = socket.gethostbyname(host)
    except OSError:
        ip = host
    if isinstance(r, ConnectionRefusedError):
        return 'Post "%s": dial tcp %s:%d: connect: connection refused' % (url, ip, port)
    if isinstance(r, (socket.timeout, TimeoutError)):
        return ('Post "%s": context deadline exceeded (Client.Timeout exceeded while '
                'awaiting headers)' % url)
    if isinstance(e, urllib.error.HTTPError):
        return "%d %s" % (e.code, e.reason)
    return 'Post "%s": %s' % (url, r)


def prom(ds, path, params):
    base = str(ds.get("url") or "").rstrip("/")
    if not base:
        return None, "datasource %s has no URL" % ds.get("name")
    if not re.match(r"https?://", base):
        return None, 'Post "%s%s": unsupported protocol scheme ""' % (base, path)
    url = base + path
    data = urllib.parse.urlencode(params).encode()
    try:
        req = urllib.request.Request(url, data=data, headers={
            "Content-Type": "application/x-www-form-urlencoded"})
        with urllib.request.urlopen(req, timeout=3) as r:
            body = r.read()
        j = json.loads(body.decode())
        if j.get("status") != "success":
            return None, "bad_response: %s" % j.get("error", "unknown")
        return j, None
    except urllib.error.HTTPError as e:
        return None, "client_error: client error: %d" % e.code
    except (urllib.error.URLError, OSError) as e:
        return None, goerr(url, e)
    except ValueError:
        return None, "bad_response: readObjectStart: expect { or n, but found <"


def default_ds():
    ps = [d for d in DS if d.get("type") == "prometheus"]
    for d in ps:
        if d.get("isDefault") is True:
            return d
    return ps[0] if ps else None


def state(ok, url, err):
    try:
        with open(STATE + ".tmp", "w") as f:
            json.dump({"pid": os.getpid(), "ok": ok, "url": url, "err": err,
                       "ts": time.time(), "n": len(DS)}, f)
        os.replace(STATE + ".tmp", STATE)
    except OSError:
        pass


def dashboards():
    while True:
        ds = default_ds()
        if not ds:
            lg("query_data", "error", "Failed to query data",
               'error="data source not found" dashboardUID=edge-box-health panelId=2',
               "")
            state(False, "", "no datasource")
        else:
            now = int(time.time())
            _, err = prom(ds, "/api/v1/query_range", {"query": "node_load1", "start": now - 3600,
                                                      "end": now, "step": 60})
            if err:
                qfail(ds, err)
            state(err is None, ds.get("url", ""), err or "")
        time.sleep(10)


def qfail(ds, err, t=None):
    lg("tsdb.prometheus", "error", "Prometheus query failed",
       'query=node_load1 error="%s"' % err.replace('"', '\\"'),
       'endpoint=queryData pluginId=prometheus dsName=%s dsUID=%s uname=admin '
       'fromAlert=false' % (ds["name"], ds["uid"]), t=t)
    lg("context", "error", "Request Completed",
       'method=POST path=/api/ds/query status=500 remote_addr=10.50.0.21 '
       'time_ms=3 duration=3.1ms size=312 referer="http://edge-nvr-03:3000/d/'
       'edge-box-health/northgate-edge-box-health?refresh=10s" '
       'handler=/api/ds/query status_source=downstream',
       "userId=1 orgId=1 uname=admin", t=t)


# ---------------------------------------------------------------- HTTP API
class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def reply(self, code, obj, ctype="application/json"):
        b = obj if isinstance(obj, bytes) else (obj.encode() if isinstance(obj, str)
                                                 else json.dumps(obj).encode())
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def authed(self):
        a = self.headers.get("Authorization", "")
        if a.startswith("Basic "):
            try:
                u, _, p = base64.b64decode(a[6:]).decode().partition(":")
                return u == USER and p == PASS
            except ValueError:
                return False
        return False

    def find(self, uid):
        for d in DS:
            if d["uid"] == uid:
                return d
        return None

    def handle_any(self):
        u = urllib.parse.urlparse(self.path)
        path = u.path.rstrip("/") or "/"
        q = {k: v[-1] for k, v in urllib.parse.parse_qs(u.query).items()}
        if path == "/api/health":
            return self.reply(200, json.dumps({"commit": COMMIT, "database": "ok",
                                               "version": VER}, indent=2) + "\n")
        if path in ("/", "/login"):
            return self.reply(200, "<!doctype html><html><head><title>Grafana</title>"
                              "</head><body></body></html>\n", "text/html; charset=UTF-8")
        if not path.startswith("/api/"):
            return self.reply(404, "<!doctype html><title>Page not found</title>\n",
                              "text/html; charset=UTF-8")
        if not self.authed():
            return self.reply(401, {"extra": None, "message": "Unauthorized",
                                    "messageId": "auth.unauthorized", "statusCode": 401,
                                    "traceID": ""})
        if path == "/api/datasources":
            return self.reply(200, json.dumps([
                {"id": i + 1, "uid": d["uid"], "orgId": 1, "name": d["name"],
                 "type": d.get("type", ""), "access": d.get("access", "proxy"),
                 "url": d.get("url", ""), "isDefault": d.get("isDefault") is True,
                 "readOnly": True} for i, d in enumerate(DS)], indent=2) + "\n")
        m = re.match(r"^/api/datasources/uid/([^/]+)/health$", path)
        if m:
            d = self.find(m.group(1))
            if not d:
                return self.reply(404, {"message": "Data source not found"})
            _, err = prom(d, "/api/v1/query", {"query": "1+1"})
            if err:
                return self.reply(400, json.dumps({"message": err + " - There was an error "
                                                   "returned querying the Prometheus API.",
                                                   "status": "ERROR"}, indent=2) + "\n")
            return self.reply(200, json.dumps({"message": "Successfully queried the "
                                               "Prometheus API.", "status": "OK"},
                                              indent=2) + "\n")
        m = re.match(r"^/api/datasources/proxy/uid/([^/]+)(/.*)$", path)
        if m:
            d = self.find(m.group(1))
            if not d:
                return self.reply(404, {"message": "Data source not found"})
            j, err = prom(d, m.group(2), q)
            if err:
                return self.reply(502, "Bad Gateway\n", "text/plain")
            return self.reply(200, json.dumps(j) + "\n")
        if path == "/api/ds/query" and self.command == "POST":
            n = int(self.headers.get("Content-Length") or 0)
            try:
                body = json.loads(self.rfile.read(n) or b"{}")
            except ValueError:
                body = {}
            res = {}
            for qq in body.get("queries") or [{"refId": "A", "expr": "up"}]:
                uid = (qq.get("datasource") or {}).get("uid")
                d = self.find(uid) if uid else default_ds()
                ref = qq.get("refId", "A")
                if not d:
                    res[ref] = {"status": 404, "error": "data source not found"}
                    continue
                j, err = prom(d, "/api/v1/query", {"query": qq.get("expr", "up")})
                if err:
                    res[ref] = {"error": err, "errorSource": "downstream", "status": 500}
                else:
                    res[ref] = {"status": 200, "frames": [{"schema": {"name": qq.get(
                        "expr", "up")}, "data": {"values": [
                            [x["value"][0] for x in j["data"]["result"]],
                            [float(x["value"][1]) for x in j["data"]["result"]]]}}]}
            return self.reply(200, json.dumps({"results": res}, indent=2) + "\n")
        return self.reply(404, {"message": "Not found"})

    do_GET = do_POST = handle_any


def main():
    procname("grafana")
    global DS
    signal.signal(signal.SIGTERM, lambda *_: (
        lg("server", "info", "Shutdown started", 'reason="System signal: terminated"'),
        sys.exit(0)))
    port = int(os.environ.get("GF_SERVER_HTTP_PORT", "3000"))
    bd = os.environ.get("MOCKD_BACKDATE")
    T = float(bd) if bd else None
    lg("settings", "info", "Starting Grafana", 'version=%s commit=%s branch=HEAD '
       'compiled=2024-08-27T16:27:25Z' % (VER, COMMIT), t=T)
    lg("settings", "info", "Config loaded from", "file=/usr/share/grafana/conf/defaults.ini", t=T)
    lg("settings", "info", "Path Provisioning", "path=" + PROV, t=T)
    lg("sqlstore", "info", "Connecting to DB", "dbtype=sqlite3", t=T)
    lg("migrator", "info", "migrations completed", "performed=0 skipped=594 duration=1.2ms", t=T)
    DS = provision()
    for d in DS:
        lg("provisioning.datasources", "info", "inserting datasource from configuration",
           "name=%s uid=%s" % (d["name"], d["uid"]), t=T)
    lg("provisioning.dashboard", "info", "starting to provision dashboards", t=T)
    lg("provisioning.dashboard", "info", "finished to provision dashboards", t=T)
    srv = None
    for _ in range(50):
        try:
            srv = ThreadingHTTPServer(("0.0.0.0", port), H)
            break
        except OSError:
            time.sleep(0.2)
    if not srv:
        lg("server", "error", "Stopped background service", 'service=*api.HTTPServer '
           'reason="failed to open listener on address 0.0.0.0:%d: listen tcp 0.0.0.0:%d: '
           'bind: address already in use"' % (port, port), t=T)
        sys.exit(1)
    lg("http.server", "info", "HTTP Server Listen", "address=[::]:%d protocol=http "
       "subUrl= socket=" % port, t=T)
    ds = default_ds()
    if T and ds:                   # history: the dashboard refreshed every minute since
        now = int(time.time())
        err = prom(ds, "/api/v1/query_range", {"query": "node_load1", "start": now - 3600,
                                                "end": now, "step": 60})[1]
        t = T + 30
        while err and t < time.time() - 15:
            qfail(ds, err, t)
            t += 60
    state(False, (ds or {}).get("url", ""), "starting")
    threading.Thread(target=dashboards, daemon=True).start()
    srv.serve_forever()


main()

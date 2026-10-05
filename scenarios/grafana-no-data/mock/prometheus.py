# drill mock: prom/prometheus v2.54 (host network). Scrapes the targets in its
# prometheus.yml for real and answers enough of the HTTP API for curl/Grafana:
# /-/ready /-/healthy /api/v1/query /api/v1/query_range /api/v1/targets
import json, os, re, signal, sys, threading, time, urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from mdcommon import procname, write, argval, host_path

VER = "2.54.1"
START = time.time()
TARGETS = {}          # "host:port" -> dict(job, health, last, err, samples)
LOCK = threading.Lock()


def ts(t=None):
    t = t or time.time()
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%03dZ" % int((t % 1) * 1000)


_BD = os.environ.get("MOCKD_BACKDATE")
T0 = float(_BD) if _BD else None       # startup lines carry the (backdated) start time


def lg(level, caller, msg, extra=""):
    t = T0 or time.time()
    write('ts=%s caller=%s level=%s msg="%s"%s' % (ts(t), caller, level, msg,
                                                     (" " + extra) if extra else ""), t)


def load_config(path):
    """tiny reader for scrape_configs: job_name + static_configs targets"""
    jobs = []
    try:
        text = open(path).read()
    except OSError as e:
        return None, str(e)
    job = None
    for ln in text.splitlines():
        m = re.match(r"\s*-\s*job_name:\s*['\"]?([\w.-]+)", ln)
        if m:
            job = m.group(1)
            continue
        m = re.match(r"\s*-?\s*targets:\s*\[(.*)\]", ln)
        if m and job:
            for t in m.group(1).split(","):
                t = t.strip().strip("'\"")
                if t:
                    jobs.append((job, t))
    return jobs, None


def scrape_loop(jobs):
    while True:
        for job, t in jobs:
            rec = TARGETS.setdefault(t, dict(job=job, health="unknown", last=0, err="",
                                             samples={}))
            try:
                with urllib.request.urlopen("http://%s/metrics" % t, timeout=2) as r:
                    body = r.read().decode("utf-8", "replace")
                s = {}
                for ln in body.splitlines():
                    if ln and not ln.startswith("#"):
                        k, _, v = ln.rpartition(" ")
                        s[k.split("{")[0]] = v
                with LOCK:
                    rec.update(health="up", last=time.time(), err="", samples=s)
            except Exception as e:
                err = getattr(e, "reason", e)
                with LOCK:
                    rec.update(health="down", last=time.time(),
                               err='Get "http://%s/metrics": %s' % (t, err))
        time.sleep(5)


def vector(q):
    q = q.strip()
    now = time.time()
    res = []
    with LOCK:
        items = list(TARGETS.items())
    if q in ("up", "up{}") or re.fullmatch(r'up\{job="[\w.-]+"\}', q):
        want = re.search(r'job="([\w.-]+)"', q)
        for t, r in items:
            if want and r["job"] != want.group(1):
                continue
            res.append({"metric": {"__name__": "up", "instance": t, "job": r["job"]},
                        "value": [now, "1" if r["health"] == "up" else "0"]})
        return res
    name = re.match(r"[a-zA-Z_:][\w:]*", q)
    if name:
        for t, r in items:
            if r["health"] == "up" and name.group(0) in r["samples"]:
                res.append({"metric": {"__name__": name.group(0), "instance": t,
                                       "job": r["job"]},
                            "value": [now, r["samples"][name.group(0)]]})
    return res


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def reply(self, code, obj, ctype="application/json"):
        b = (json.dumps(obj) if not isinstance(obj, (str, bytes)) else obj)
        b = b.encode() if isinstance(b, str) else b
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def params(self):
        u = urllib.parse.urlparse(self.path)
        p = urllib.parse.parse_qs(u.query)
        if self.command == "POST":
            n = int(self.headers.get("Content-Length") or 0)
            p.update(urllib.parse.parse_qs(self.rfile.read(n).decode()))
        return u.path, {k: v[-1] for k, v in p.items()}

    def handle_any(self):
        path, p = self.params()
        if path == "/-/ready":
            return self.reply(200, "Prometheus Server is Ready.\n", "text/plain")
        if path == "/-/healthy":
            return self.reply(200, "Prometheus Server is Healthy.\n", "text/plain")
        if path in ("/api/v1/query", "/api/v1/query_range"):
            q = p.get("query")
            if not q:
                return self.reply(400, {"status": "error", "errorType": "bad_data",
                                        "error": "1:1: parse error: no expression found in "
                                                 "input"})
            v = vector(q)
            if path.endswith("_range"):
                now = time.time()
                data = {"resultType": "matrix", "result": [
                    {"metric": x["metric"], "values": [[now - 60 * i, x["value"][1]]
                                                      for i in range(5, -1, -1)]}
                    for x in v]}
            else:
                data = {"resultType": "vector", "result": v}
            return self.reply(200, {"status": "success", "data": data})
        if path == "/api/v1/targets":
            with LOCK:
                act = [{"labels": {"instance": t, "job": r["job"]}, "scrapeUrl":
                        "http://%s/metrics" % t, "health": r["health"],
                        "lastError": r["err"], "lastScrape": ts(r["last"])}
                       for t, r in TARGETS.items()]
            return self.reply(200, {"status": "success", "data": {"activeTargets": act,
                                                                  "droppedTargets": []}})
        if path == "/metrics":
            with LOCK:
                n = len(TARGETS)
            return self.reply(200, "# HELP prometheus_build_info A metric with a constant '1' "
                              "value.\n# TYPE prometheus_build_info gauge\n"
                              'prometheus_build_info{version="%s"} 1\n'
                              "# HELP prometheus_sd_discovered_targets Current number of "
                              "discovered targets.\n# TYPE prometheus_sd_discovered_targets "
                              "gauge\nprometheus_sd_discovered_targets %d\n"
                              "process_start_time_seconds %.2f\n" % (VER, n, START),
                              "text/plain; version=0.0.4; charset=utf-8")
        if path == "/api/v1/status/buildinfo":
            return self.reply(200, {"status": "success", "data": {"version": VER,
                                                                  "goVersion": "go1.22.6"}})
        if path in ("/", "/graph"):
            return self.reply(200, "<html><head><title>Prometheus Time Series Collection "
                              "and Processing Server</title></head><body></body></html>\n",
                              "text/html; charset=utf-8")
        return self.reply(404, "404 page not found\n", "text/plain; charset=utf-8")

    do_GET = do_POST = handle_any


def main():
    procname("prometheus")
    signal.signal(signal.SIGTERM, lambda *_: (
        lg("warn", "main.go:900", "Received SIGTERM, exiting gracefully..."), sys.exit(0)))
    addr = argval("--web.listen-address", "0.0.0.0:9090")
    cfg = argval("--config.file", "/etc/prometheus/prometheus.yml")
    host, _, port = addr.rpartition(":")
    lg("info", "main.go:601", "No time or size retention was set so using the default time "
       "retention", "duration=15d")
    lg("info", "main.go:645", "Starting Prometheus Server", 'mode=server version="(version=%s, '
       'branch=HEAD, revision=e6cfa720fbe6280153fab13090a483dbd40bece3)"' % VER)
    lg("info", "main.go:1134", "Loading configuration file", "filename=" + cfg)
    jobs, err = load_config(host_path(cfg) or cfg)
    if jobs is None:
        lg("error", "main.go:1189", "Error loading config (--config.file=%s)" % cfg,
           'file=%s err="open %s: no such file or directory"' % (cfg, cfg))
        sys.exit(2)
    lg("info", "main.go:1171", "Completed loading of configuration file", "filename=%s "
       "totalDuration=1.24ms" % cfg)
    srv = None
    for _ in range(50):
        try:
            srv = ThreadingHTTPServer((host or "0.0.0.0", int(port)), H)
            break
        except OSError:
            time.sleep(0.2)
    if not srv:
        lg("error", "main.go:1066", "Unable to start web listener", 'err="listen tcp %s: '
           'bind: address already in use"' % addr)
        sys.exit(1)
    lg("info", "web.go:571", "Start listening for connections", "component=web address=" + addr)
    threading.Thread(target=scrape_loop, args=(jobs,), daemon=True).start()
    lg("info", "main.go:1149", "Server is ready to receive web requests.")
    lg("info", "manager.go:164", "Starting rule manager...", "component=\"rule manager\"")
    global T0
    T0 = None
    srv.serve_forever()


main()

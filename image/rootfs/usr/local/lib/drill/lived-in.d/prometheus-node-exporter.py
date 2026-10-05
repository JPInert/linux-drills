# drill lived-in noise: node_exporter 1.5.0 on :9100, /metrics from the real /proc.
import ctypes, http.server, os, socketserver, time
ctypes.CDLL(None).prctl(15, b"prometheus-node", 0, 0, 0)


def ts():
    t = time.time()
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%03dZ" % (t % 1 * 1000)


def log(caller, msg):
    print("ts=%s caller=%s level=info %s" % (ts(), caller, msg), flush=True)


def metrics():
    L = ["# HELP node_exporter_build_info A metric with a constant '1' value labeled by "
         "version, revision, branch, goversion from which node_exporter was built, and the "
         "goos and goarch for the build.", "# TYPE node_exporter_build_info gauge",
         'node_exporter_build_info{branch="debian/sid",goarch="amd64",goos="linux",'
         'goversion="go1.19.8",revision="1.5.0-1+b6",version="1.5.0"} 1']
    try:
        l1, l5, l15 = open("/proc/loadavg").read().split()[:3]
        for n, v in (("load1", l1), ("load5", l5), ("load15", l15)):
            L += ["# HELP node_%s %s load average." % (n, n[4:] + "m"),
                  "# TYPE node_%s gauge" % n, "node_%s %s" % (n, v)]
        mem = dict((ln.split(":")[0], int(ln.split()[1]) * 1024)
                   for ln in open("/proc/meminfo") if len(ln.split()) >= 2)
        for k in ("MemTotal", "MemFree", "MemAvailable", "Buffers", "Cached", "SwapTotal",
                  "SwapFree"):
            L += ["# HELP node_memory_%s_bytes Memory information field %s_bytes." % (k, k),
                  "# TYPE node_memory_%s_bytes gauge" % k,
                  "node_memory_%s_bytes %.6e" % (k, mem.get(k, 0))]
        cpu = open("/proc/stat").readline().split()[1:9]
        L += ["# HELP node_cpu_seconds_total Seconds the CPUs spent in each mode.",
              "# TYPE node_cpu_seconds_total counter"]
        for m, v in zip(("user", "nice", "system", "idle", "iowait", "irq", "softirq",
                         "steal"), cpu):
            L.append('node_cpu_seconds_total{cpu="0",mode="%s"} %.2f' % (m, int(v) / 100.0))
        st = os.statvfs("/")
        L += ["# HELP node_filesystem_avail_bytes Filesystem space available to non-root "
              "users in bytes.", "# TYPE node_filesystem_avail_bytes gauge",
              'node_filesystem_avail_bytes{device="/dev/nvme0n1p2",fstype="ext4",'
              'mountpoint="/"} %.6e' % (st.f_bavail * st.f_frsize),
              "# HELP node_time_seconds System time in seconds since epoch (1970).",
              "# TYPE node_time_seconds gauge", "node_time_seconds %.9e" % time.time()]
        L += ["# HELP node_uname_info Labeled system information as provided by the uname "
              "system call.", "# TYPE node_uname_info gauge",
              'node_uname_info{domainname="(none)",machine="x86_64",nodename="%s",'
              'release="%s",sysname="Linux"} 1' % (os.uname().nodename, os.uname().release)]
    except (OSError, ValueError):
        pass
    return ("\n".join(L) + "\n").encode()


class H(http.server.BaseHTTPRequestHandler):
    server_version, sys_version = "", ""

    def log_message(self, *a):            # quiet, like the real one
        pass

    def do_GET(self):
        if self.path.split("?")[0] == "/metrics":
            body, ct = metrics(), "text/plain; version=0.0.4; charset=utf-8"
        else:
            body = (b"<html>\n<head><title>Node Exporter</title></head>\n<body>\n<h1>Node "
                    b"Exporter</h1>\n<p><a href=\"/metrics\">Metrics</a></p>\n</body>\n</html>\n")
            ct = "text/html; charset=UTF-8"
        self.send_response(200)
        self.send_header("Content-Type", ct)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
    address_family, daemon_threads, allow_reuse_address = 10, True, True   # AF_INET6: [::]:9100


log("node_exporter.go:180", 'msg="Starting node_exporter" version="(version=1.5.0, '
    'branch=debian/sid, revision=1.5.0-1+b6)"')
log("node_exporter.go:181", 'msg="Build context" build_context="(go=go1.19.8, '
    'user=maintainers, date=20230411-19:08:00)"')
log("filesystem_common.go:111", 'collector=filesystem msg="Parsed flag '
    '--collector.filesystem.mount-points-exclude" flag=^/(dev|proc|run|sys|mnt|media|'
    'var/lib/docker/.+|var/lib/containers/storage/.+)($|/)')
log("node_exporter.go:110", 'msg="Enabled collectors"')
for c in ("arp", "bcache", "bonding", "conntrack", "cpu", "diskstats", "edac", "filesystem",
          "hwmon", "loadavg", "meminfo", "netdev", "netstat", "systemd", "textfile",
          "thermal_zone", "time", "uname", "vmstat"):
    log("node_exporter.go:117", "collector=" + c)
try:
    srv = S(("::", 9100), H)
except OSError:                          # no IPv6 in this box: plain IPv4
    S.address_family = 2
    srv = S(("0.0.0.0", 9100), H)
log("tls_config.go:232", 'msg="Listening on" address=[::]:9100')
log("tls_config.go:235", 'msg="TLS is disabled." http2=false address=[::]:9100')
srv.serve_forever()

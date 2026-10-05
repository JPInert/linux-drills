# drill lived-in noise: Grafana Agent (static mode) idling, HTTP on 127.0.0.1:12345.
import ctypes, http.server, time
ctypes.CDLL(None).prctl(15, b"grafana-agent", 0, 0, 0)


def log(level, msg):
    t = time.time()
    print("%sts=%s level=%s %s" % ("<4>" if level == "warn" else "",
                                   time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) +
                                   ".%09dZ" % int(t % 1 * 1e9), level, msg), flush=True)


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        body = b"Agent is Ready.\n" if self.path.startswith("/-/ready") else \
            b'# HELP agent_build_info A metric with a constant \'1\' value.\n' \
            b'agent_build_info{version="v0.40.4"} 1\n'
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


log("info", 'caller=main.go:73 msg="boringcrypto enabled" enabled=false')
log("info", 'caller=server.go:190 msg="server listening on addresses" '
    'http=127.0.0.1:12345 grpc=127.0.0.1:12346')
log("info", 'caller=node.go:85 agent=prometheus component=cluster msg="applying config"')
log("info", 'caller=remote.go:180 agent=prometheus instance=5a3f0b7d9e2c component=manager '
    'msg="Starting WAL watcher" queue=5a3f0b7d9e2c-2f0c1a')
log("warn", 'caller=main.go:57 msg="static mode is deprecated and will be removed in '
    'a future release; see the migration guide to Grafana Alloy"')
log("info", 'caller=wal.go:254 agent=prometheus instance=5a3f0b7d9e2c msg="WAL replay '
    'completed" duration=41.2ms')
log("info", 'caller=integrations.go:156 msg="integrations enabled" '
    'integrations=agent,node_exporter')
http.server.HTTPServer(("127.0.0.1", 12345), H).serve_forever()

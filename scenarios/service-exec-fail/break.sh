# wait until systemd is fully up (the harness can race a busy host)
for i in $(seq 1 120); do case $(systemctl is-system-running 2>/dev/null) in running|degraded) break ;; esac; sleep 0.5; done
useradd -r -s /usr/sbin/nologin -M feedrelay 2>/dev/null || true
install -d -m 0755 /opt/feedrelay /opt/feedrelay/bin
cat > /opt/feedrelay/relay.py <<'PY'
# feedrelay: stand-in for the camera stream relay
import http.server, socketserver, sys
port = int(sys.argv[sys.argv.index("--port") + 1]) if "--port" in sys.argv else 8091
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Type", "text/plain"); self.end_headers()
        self.wfile.write(b"feedrelay ok: 4 streams relayed\n")
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer(("0.0.0.0", port), H).serve_forever()
PY
cat > /opt/feedrelay/bin/run.sh <<'SH'
#!/bin/bash
# feedrelay launcher (v3.1)
exec /usr/bin/python3 /opt/feedrelay/relay.py --port 8091
SH
# "redeployed from a zip": nothing keeps its execute bit
chmod 0644 /opt/feedrelay/relay.py /opt/feedrelay/bin/run.sh
# unit still points at the old release layout (/opt/feedrelay/current went away in v3)
cat > /etc/systemd/system/feedrelay.service <<'UNIT'
[Unit]
Description=Feed relay (camera streams to the guard station)
After=network.target

[Service]
User=feedrelay
WorkingDirectory=/opt/feedrelay/current
ExecStart=/opt/feedrelay/bin/run.sh

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable feedrelay >/dev/null 2>&1
systemctl start feedrelay || true      # the update's post-install start fails
sleep 1

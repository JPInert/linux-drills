# wait until systemd is fully up (the harness can race a busy host)
for i in $(seq 1 120); do case $(systemctl is-system-running 2>/dev/null) in running|degraded) break ;; esac; sleep 0.5; done
useradd -r -s /usr/sbin/nologin -M camwatch 2>/dev/null || true
install -d /opt/camwatch
cat > /opt/camwatch/camwatch.py <<'PY'
# camwatch: stand-in for the camera-feed relay the guard station polls
import http.server, socketserver
BODY = b"<html><head><title>camwatch relay</title></head><body><h1>camwatch relay</h1><p>feeds: cam-01 cam-02 cam-03 cam-04 up</p></body></html>\n"
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Type", "text/html"); self.end_headers()
        self.wfile.write(BODY)
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer(("0.0.0.0", 8090), H).serve_forever()
PY
chmod 0644 /opt/camwatch/camwatch.py
# installed by the update package, but never enabled and not running after the reboot
cat > /etc/systemd/system/camwatch.service <<'UNIT'
[Unit]
Description=Camera feed relay (guard station)
After=network.target

[Service]
User=camwatch
ExecStart=/usr/bin/python3 /opt/camwatch/camwatch.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
sleep 1

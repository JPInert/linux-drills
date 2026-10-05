useradd -m -s /bin/bash deploy 2>/dev/null || true
useradd -r -s /usr/sbin/nologin -M dashboard 2>/dev/null || true
install -d -o dashboard -g dashboard /srv/dashboard
cat > /srv/dashboard/index.html <<'HTML'
<html><head><title>Facility Dashboard</title></head><body><h1>Facility Dashboard</h1><p>cameras: 4 online</p></body></html>
HTML
chown dashboard:dashboard /srv/dashboard/index.html
cat > /etc/systemd/system/dashboard.service <<'UNIT'
[Unit]
Description=Camera dashboard (web)
After=network.target

[Service]
User=dashboard
WorkingDirectory=/srv/dashboard
ExecStart=/usr/bin/python3 -m http.server 8080 --bind 0.0.0.0
Restart=no

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable dashboard >/dev/null 2>&1
# a stale preview server, left running by a developer, that ignores SIGTERM
cat > /home/deploy/preview.py <<'PY'
import http.server, signal, socketserver
signal.signal(signal.SIGTERM, signal.SIG_IGN)
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Type", "text/html"); self.end_headers()
        self.wfile.write(b"<html><title>PREVIEW BUILD (old)</title><h1>preview build - do not use</h1></html>\n")
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer(("0.0.0.0", 8080), H).serve_forever()
PY
chown deploy:deploy /home/deploy/preview.py
su -s /bin/bash deploy -c 'cd ~ && setsid nohup python3 /home/deploy/preview.py >/dev/null 2>&1 &'
sleep 1
systemctl start dashboard || true      # boot-time start: loses the race
sleep 1

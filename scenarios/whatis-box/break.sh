/usr/local/lib/drill/analytics-install --no-start
/usr/local/lib/drill/lived-in
python3 - <<'PY'
import os, random, socket, subprocess, time
r = random.Random(os.urandom(16))
def free(p):
    s = socket.socket()
    try:
        s.bind(("0.0.0.0", p)); return True
    except OSError:
        return False
    finally:
        s.close()
cams = r.choice([6, 7, 8, 10, 12, 14, 16])
port = r.choice([p for p in (7001, 8000, 8081, 8088, 8443, 8880, 9080, 9443) if free(p)])
models = ["vehicle-count-v3.1.engine", "vehicle-count-v3.2.engine", "fall-pose-v4.engine",
          "person-fall-yolo8s.engine", "bed-exit-v2.engine", "vehicle-count-v2.9.engine"]
r.shuffle(models)
used, others = models[0], models[1:4]
d = "/opt/analytics/models"
os.makedirs(d, exist_ok=True)
now = time.time()
for i, m in enumerate([used] + others):
    with open(os.path.join(d, m), "wb") as f:
        f.write(os.urandom(r.randint(40, 90) * 1024))
    age = r.randint(20, 90) * 86400 if m == used else r.randint(1, 60) * 86400
    os.utime(os.path.join(d, m), (now - age, now - age))
pv = os.path.join(d, "person-vehicle.engine")      # the install default (empty, from the image)
if os.path.exists(pv):
    os.utime(pv, (now - 150 * 86400, now - 150 * 86400))
# the newest file in the folder is a staged update nobody switched to
stage = others[0]
os.utime(os.path.join(d, stage), (now - 3600, now - 3600))
c = open("/etc/analytics/analytics.conf").read()
c = c.replace("CAMERAS=4", "CAMERAS=%d" % cams).replace("MODEL=/opt/analytics/models/person-vehicle.engine", "MODEL=%s/%s" % (d, used))
open("/etc/analytics/analytics.conf", "w").write(c)
os.makedirs("/opt/nvr-web", exist_ok=True); os.makedirs("/srv/nvr-web", exist_ok=True)
open("/srv/nvr-web/index.html", "w").write("<html><title>NVR web</title><h1>Northgate Garage NVR</h1></html>\n")
open("/opt/nvr-web/nvr-web", "w").write("""#!/usr/bin/python3
import http.server, os, socketserver
os.chdir("/srv/nvr-web")
class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
socketserver.ThreadingTCPServer(("0.0.0.0", %d), H).serve_forever()
""" % port)
os.chmod("/opt/nvr-web/nvr-web", 0o755)
open("/etc/systemd/system/nvr-web.service", "w").write("""[Unit]
Description=NVR web UI
After=network.target

[Service]
ExecStart=/opt/nvr-web/nvr-web
Restart=on-failure

[Install]
WantedBy=multi-user.target
""")
with open("/var/lib/drill/.expected", "w") as f:
    f.write("EXP_CAMS=%d\nEXP_WEB=%d\nEXP_MODEL=%s\nEXP_STAGE=%s\n" % (cams, port, used, stage))
os.chmod("/var/lib/drill/.expected", 0o600)
PY
systemctl daemon-reload
systemctl enable --now nvr-web >/dev/null 2>&1
systemctl start analytics
. /var/lib/drill/.expected
for i in $(seq 50); do ss -tln | grep -q ":$EXP_WEB " && [ -s /run/mock-gpu/analytics.json ] && break; sleep 0.1; done
# the one failed unit (lived-in plants it); record its name for check
f=$(systemctl list-units --failed --plain --no-legend --type=service | cut -d' ' -f1 | head -1)
[ -n "$f" ] || { echo "whatis-box: lived-in planted no failed unit" >&2; exit 1; }
echo "EXP_FAILED=${f%.service}" >> /var/lib/drill/.expected

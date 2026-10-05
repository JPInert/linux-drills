# baseline: the real analytics service is one of the legitimate residents
/usr/local/lib/drill/analytics-install
install -d /opt/frame-indexer /opt/videoproc /opt/nvr-web /srv/nvr-web
echo '<html><title>NVR web</title><h1>NVR web</h1></html>' > /srv/nvr-web/index.html

# --- the runaway: a python busy loop. The script's own name becomes the process name in top/ps.
cat > /opt/frame-indexer/frame-indexer <<'PY'
#!/usr/bin/python3
import sys, time
print("frame-indexer: starting full re-index of /var/spool/frames (queue=0)", flush=True)
passes, last = 0, 0.0
while True:
    x = 0
    for i in range(300000):          # "indexing"
        x += (i * i) % 7
    passes += 1
    if time.time() - last >= 10:
        last = time.time()
        print("frame-indexer: pass %d done: 0 frames indexed, queue still 0, starting over" % passes, flush=True)
PY
# --- legitimate low-CPU residents
cat > /opt/videoproc/videoproc <<'PY'
#!/usr/bin/python3
import time
print("videoproc: transcoder pool up (4 slots)", flush=True)
while True:
    t = time.time()
    while time.time() - t < 0.03:    # a few ms of "work" each cycle
        pass
    time.sleep(0.7)
PY
cat > /opt/nvr-web/nvr-web <<'PY'
#!/usr/bin/python3
import http.server, os, socketserver, threading, time
os.chdir("/srv/nvr-web")
def tick():
    while True:
        t = time.time()
        while time.time() - t < 0.005:
            pass
        time.sleep(1)
threading.Thread(target=tick, daemon=True).start()
class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
socketserver.ThreadingTCPServer(("0.0.0.0", 8088), H).serve_forever()
PY
chmod 0755 /opt/frame-indexer/frame-indexer /opt/videoproc/videoproc /opt/nvr-web/nvr-web

mkunit() {  # mkunit <name> <description> <restart-policy>
cat > /usr/lib/systemd/system/$1.service <<UNIT
[Unit]
Description=$2
After=network.target

[Service]
ExecStart=/opt/$1/$1
Restart=$3
RestartSec=1
CPUAccounting=yes
MemoryAccounting=yes

[Install]
WantedBy=multi-user.target
UNIT
}
mkunit frame-indexer "Frame index builder (thumbnail search index)" always
mkunit videoproc     "Video transcoder pool"                        on-failure
mkunit nvr-web       "NVR web UI"                                   on-failure
systemctl daemon-reload
systemctl enable --now videoproc nvr-web frame-indexer >/dev/null 2>&1
sleep 4

/usr/local/lib/drill/analytics-install --no-start
id ollama >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin -m -d /usr/share/ollama ollama
chmod 1777 /run/mock-gpu          # analytics AND ollama publish their GPU use here for the nvidia-smi mock

# --- mock ollama: `serve` is the daemon; ps / list / stop / run talk to it over :11434 like the real CLI
cat > /usr/local/bin/ollama <<'PY'
#!/usr/bin/python3
# drill mock of ollama (no model, no GPU): holds ~11 GB of the mock GPU while a model is loaded
import json, os, signal, sys, threading, time, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST, PORT = "127.0.0.1", 11434
STATE = "/run/mock-gpu/ollama.json"
MODEL, MID, MIB = "llama3.1:8b", "46e0c10c039e", 10960
loaded = {}

def log(level, msg):
    print('time=%s level=%s source=server.go msg="%s"' % (time.strftime("%Y-%m-%dT%H:%M:%S.000-04:00"), level, msg), flush=True)

def publish():
    if loaded:
        with open(STATE, "w") as f:
            json.dump({"pid": os.getpid(), "name": "/usr/local/bin/ollama runner", "mem_mib": MIB, "util": 1}, f)
    else:
        try: os.remove(STATE)
        except FileNotFoundError: pass

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body, ctype="application/json"):
        b = body.encode(); self.send_response(code); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path == "/":
            return self.send(200, "Ollama is running", "text/plain")
        if self.path == "/api/ps":
            return self.send(200, json.dumps({"models": [{"name": MODEL, "digest": MID, "size_vram": MIB << 20, "expires_at": "forever"}] if loaded else []}))
        if self.path == "/api/tags":
            return self.send(200, json.dumps({"models": [{"name": MODEL, "digest": MID, "size": 8540000000, "modified": "25 hours ago"}]}))
        self.send(404, "404 page not found", "text/plain")
    def do_POST(self):
        if self.path == "/api/load":
            if not loaded:
                log("INFO", "starting llama server")
                print("llm_load_tensors: offloading 32 repeating layers to GPU", flush=True)
                print("llm_load_tensors: offloaded 33/33 layers to GPU", flush=True)
                print("llm_load_tensors:      CUDA0 buffer size = %d.00 MiB" % MIB, flush=True)
                loaded[MODEL] = time.time(); publish()
                log("INFO", "llama runner started in 4.02 seconds")
            return self.send(200, "{}")
        if self.path == "/api/stop":
            loaded.clear(); publish(); log("INFO", "model unloaded: %s" % MODEL)
            return self.send(200, "{}")
        self.send(404, "404 page not found", "text/plain")

def serve():
    def bye(*_):
        loaded.clear(); publish(); sys.exit(0)
    signal.signal(signal.SIGTERM, bye)
    log("INFO", "Listening on %s:%d (version 0.3.12)" % (HOST, PORT))
    log("INFO", 'inference compute id=GPU-3f0c6b1e-8a52-9d47-1c0e-5b7a2d9e4f10 library=cuda compute=8.6 name=\\"NVIDIA RTX A2000 12GB\\" total=\\"11.8 GiB\\" available=\\"11.6 GiB\\"')
    def beat():
        while True:
            time.sleep(2); publish()
    threading.Thread(target=beat, daemon=True).start()
    ThreadingHTTPServer((HOST, PORT), H).serve_forever()

def call(method, path, wait=0):
    for _ in range(wait):                       # `run` right after `serve` starts: wait for the port
        try:
            urllib.request.urlopen("http://%s:%d/" % (HOST, PORT), timeout=1); break
        except OSError:
            time.sleep(0.5)
    try:
        r = urllib.request.urlopen(urllib.request.Request("http://%s:%d%s" % (HOST, PORT, path), method=method, data=b"{}" if method == "POST" else None), timeout=5)
        return json.loads(r.read() or b"{}")
    except OSError:
        print("Error: could not connect to ollama app, is it running?", file=sys.stderr); sys.exit(1)

a = sys.argv[1:]
cmd = a[0] if a else ""
if cmd == "serve":
    serve()
elif cmd == "ps":
    ms = call("GET", "/api/ps")["models"]
    print("%-20s %-14s %-9s %-10s %s" % ("NAME", "ID", "SIZE", "PROCESSOR", "UNTIL"))
    for m in ms:
        print("%-20s %-14s %-9s %-10s %s" % (m["name"], m["digest"], "%d GB" % round(m["size_vram"] / 2**30), "100% GPU", "Forever"))
elif cmd == "list":
    ms = call("GET", "/api/tags")["models"]
    print("%-20s %-14s %-9s %s" % ("NAME", "ID", "SIZE", "MODIFIED"))
    for m in ms:
        print("%-20s %-14s %-9s %s" % (m["name"], m["digest"], "4.9 GB", m["modified"]))
elif cmd == "stop" and len(a) > 1:
    call("POST", "/api/stop")
elif cmd == "run" and len(a) > 1:
    call("POST", "/api/load", wait=20)
elif cmd in ("-v", "--version"):
    print("ollama version is 0.3.12")
else:
    print("Usage:\n  ollama [command]\n\nAvailable Commands:\n  serve  Start ollama\n  run    Run a model\n  stop   Stop a running model\n  list   List models\n  ps     List running models", file=sys.stderr)
    sys.exit(0 if cmd in ("", "help", "-h", "--help") else 1)
PY
chmod 0755 /usr/local/bin/ollama

# the unit the ollama install script writes, plus the pilot's `systemctl edit` override
cat > /etc/systemd/system/ollama.service <<'UNIT'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=default.target
UNIT
install -d /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<'UNIT'
# incident-summary pilot: keep the model resident so the first summary is fast
[Service]
Environment="OLLAMA_KEEP_ALIVE=-1"
ExecStartPost=/bin/sh -c 'sleep 1; /usr/local/bin/ollama run llama3.1:8b ""'
UNIT
systemctl daemon-reload
systemctl enable ollama >/dev/null 2>&1

# yesterday's order of events: the pilot loaded its model, then analytics restarted and found no room
systemctl start ollama
for _ in $(seq 1 30); do [ -f /run/mock-gpu/ollama.json ] && break; sleep 0.5; done
[ -f /run/mock-gpu/ollama.json ]
systemctl start analytics
for _ in $(seq 1 20); do grep -q 'device=cpu' /var/log/analytics/detect.log 2>/dev/null && break; sleep 0.5; done
grep -q 'device=cpu' /var/log/analytics/detect.log

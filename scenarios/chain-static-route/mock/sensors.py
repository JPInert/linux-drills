#!/usr/bin/python3
"""LAB STAND-IN for the two sensor hubs on the sensor VLAN (they are not really on this box)."""
import http.server, json, socketserver, threading, time

HUBS = {"10.60.0.20": ("bed-exit hub", 14), "10.60.0.21": ("door hub", 9)}


def handler(ip):
    name, n = HUBS[ip]

    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            body = json.dumps({"hub": name, "ip": ip, "sensors": n, "online": n,
                               "at": time.strftime("%Y-%m-%dT%H:%M:%S")}).encode() + b"\n"
            self.send_response(200); self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

        def log_message(self, *a):
            pass
    return H


class S(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


for ip in HUBS:
    threading.Thread(target=S((ip, 80), handler(ip)).serve_forever, daemon=True).start()
while True:
    time.sleep(3600)

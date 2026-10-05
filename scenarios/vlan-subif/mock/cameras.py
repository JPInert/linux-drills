#!/usr/bin/python3
"""LAB STAND-IN for camera1/camera2 on camera VLAN 50 (they are not really on this box): RTSP DESCRIBE only."""
import socketserver, threading, time

CAMS = {"10.50.50.31": "camera1", "10.50.50.32": "camera2"}


def handler(ip):
    class R(socketserver.StreamRequestHandler):
        def handle(self):
            self.connection.settimeout(10)
            try:
                line = self.rfile.readline(4096).decode("latin-1").split()
                cseq = "0"
                while True:
                    h = self.rfile.readline(4096)
                    if not h or not h.strip():
                        break
                    k, _, v = h.decode("latin-1").partition(":")
                    if k.strip().lower() == "cseq":
                        cseq = v.strip()
            except OSError:
                return
            sdp = "v=0\r\no=- 1 1 IN IP4 %s\r\ns=%s main stream\r\nm=video 0 RTP/AVP 96\r\na=rtpmap:96 H264/90000\r\n" % (ip, CAMS[ip])
            if len(line) == 3 and line[0] in ("DESCRIBE", "OPTIONS"):
                body = sdp if line[0] == "DESCRIBE" else ""
                out = "RTSP/1.0 200 OK\r\nCSeq: %s\r\nServer: %s-rtsp/2.4\r\nContent-Length: %d\r\n\r\n%s" % (cseq, CAMS[ip], len(body), body)
            else:
                out = "RTSP/1.0 400 Bad Request\r\nCSeq: %s\r\n\r\n" % cseq
            self.wfile.write(out.encode())
    return R


class S(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


for ip in CAMS:
    threading.Thread(target=S((ip, 554), handler(ip)).serve_forever, daemon=True).start()
while True:
    time.sleep(3600)

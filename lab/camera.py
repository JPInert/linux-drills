#!/usr/bin/env python3
"""camera1: a web UI that only answers the NVR's registered address (10.50.0.50)."""
import http.server, socketserver

ALLOWED = "10.50.0.50"


class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.client_address[0] != ALLOWED:
            self.send_response(403); body = b"403 Forbidden\n"
        else:
            self.send_response(200); body = b"camera1 - RTSP relay OK - stream 1080p30\n"
        self.send_header("Content-Type", "text/plain"); self.send_header("Content-Length", str(len(body)))
        self.end_headers(); self.wfile.write(body)

    def log_message(self, *a):
        pass


# ---- RTSP/1.0 on :554 (rtsp-stream-auth): just enough for `curl rtsp://` and nc. RTSP sets up the
# session; RTP would carry the video, and this mock never sends any. Any client IP; Basic auth.
import base64, threading

RTSP_USER, RTSP_PASS = "nvr", "HR-cam1-4471"          # the install-sheet value (a mock camera)
RTSP_PATH = "/Streaming/Channels/101"
SDP = ("v=0\r\no=- 1700000000 1 IN IP4 10.50.1.31\r\ns=camera1 main stream\r\nc=IN IP4 0.0.0.0\r\n"
       "t=0 0\r\na=control:*\r\nm=video 0 RTP/AVP 96\r\na=rtpmap:96 H264/90000\r\n"
       "a=fmtp:96 packetization-mode=1;profile-level-id=640028\r\na=framesize:96 1920-1080\r\n"
       "a=control:trackID=1\r\n")


class R(socketserver.StreamRequestHandler):
    def reply(self, code, reason, cseq, headers=(), body=""):
        b = body.encode()
        out = "RTSP/1.0 %d %s\r\nCSeq: %s\r\nServer: camera1-rtsp/2.4\r\n" % (code, reason, cseq)
        out += "".join("%s: %s\r\n" % h for h in headers)
        out += "Content-Length: %d\r\n\r\n" % len(b)
        self.wfile.write(out.encode() + b); self.wfile.flush()

    def handle(self):
        self.connection.settimeout(30)
        while True:
            try:
                line = self.rfile.readline(4096)
            except OSError:
                return
            if not line:
                return
            line = line.decode("latin-1").strip()
            if not line:
                continue                                  # stray blank lines (typing into nc)
            hdrs = {}
            while True:
                h = self.rfile.readline(4096)
                if not h or not h.strip():
                    break
                k, _, v = h.decode("latin-1").partition(":")
                hdrs[k.strip().lower()] = v.strip()
            if int(hdrs.get("content-length", "0") or 0):
                self.rfile.read(int(hdrs["content-length"]))
            parts = line.split()
            cseq = hdrs.get("cseq", "0")
            if len(parts) != 3 or not parts[2].startswith("RTSP/"):
                self.reply(400, "Bad Request", cseq); return
            method, url = parts[0].upper(), parts[1]
            path = "/" + url.split("://", 1)[-1].partition("/")[2] if "://" in url else url
            path = path.split("?")[0].rstrip("/") or "/"
            auth = hdrs.get("authorization", "")
            good = "Basic " + base64.b64encode(("%s:%s" % (RTSP_USER, RTSP_PASS)).encode()).decode()
            if method == "OPTIONS":                       # no login needed, but a login that IS sent is checked
                if auth and auth != good:                 # (curl's rtsp:// only ever sends OPTIONS)
                    self.reply(401, "Unauthorized", cseq, [("WWW-Authenticate", 'Basic realm="camera1"')])
                else:
                    self.reply(200, "OK", cseq, [("Public", "OPTIONS, DESCRIBE, SETUP, PLAY, PAUSE, TEARDOWN, GET_PARAMETER")])
            elif method == "DESCRIBE":
                if auth != good:
                    self.reply(401, "Unauthorized", cseq, [("WWW-Authenticate", 'Basic realm="camera1"')])
                elif path != RTSP_PATH:
                    self.reply(404, "Not Found", cseq)
                else:
                    self.reply(200, "OK", cseq, [("Content-Base", "rtsp://10.50.1.31:554%s/" % RTSP_PATH),
                                                 ("Content-Type", "application/sdp")], SDP)
            else:
                self.reply(405, "Method Not Allowed", cseq, [("Allow", "OPTIONS, DESCRIBE")])


class RS(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


_rtsp = RS(("0.0.0.0", 554), R)
threading.Thread(target=_rtsp.serve_forever, daemon=True).start()

socketserver.ThreadingTCPServer.allow_reuse_address = True
socketserver.ThreadingTCPServer(("0.0.0.0", 80), H).serve_forever()

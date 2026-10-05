# drill mock: the rtsp-relay container's process (MediaMTX-style RTSP relay)
# Listens on :8554 (host network) so `ss -ltnp` shows the video path is up.
import json, os, signal, socket, sys, threading, time

LOG = os.environ.get("MOCKD_LOG", "/dev/null")


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%09dZ" % int((t % 1) * 1e9)


def write(lines, t=None):
    t = time.time() if t is None else t
    with open(LOG, "a") as f:
        for ln in lines:
            f.write(json.dumps({"log": "%s %s\n" % (time.strftime("%Y/%m/%d %H:%M:%S",
                                                                  time.localtime(t)), ln),
                                "stream": "stdout", "time": iso(t)}) + "\n")


def main():
    signal.signal(signal.SIGTERM, lambda *_: (write(["INF shutting down gracefully"]),
                                              sys.exit(0)))
    bd = os.environ.get("MOCKD_BACKDATE")
    t0 = float(bd) if bd else time.time()
    write(["INF MediaMTX v1.9.2", "INF configuration loaded from /config/mediamtx.yml",
           "INF [RTSP] listener opened on :8554 (TCP), :8000 (UDP/RTP), :8001 (UDP/RTCP)"],
          t0)
    write(["INF [path cam%02d] [RTSP source] ready: 1 track (H264)" % i
           for i in range(1, 7)], t0 + 2)
    write(["INF [RTSP] [session %08x] is reading from path 'cam%02d', with TCP, 1 track "
           "(H264)" % (0x5c2a1e00 + i, i) for i in range(1, 7)], t0 + 9)
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(("0.0.0.0", 8554))
        s.listen(16)
    except OSError:
        s = None
    if s:
        def serve():
            while True:
                c, _ = s.accept()
                try:
                    c.sendall(b"RTSP/1.0 200 OK\r\nCSeq: 1\r\nServer: MediaMTX\r\n"
                              b"Public: DESCRIBE, SETUP, PLAY, TEARDOWN\r\n\r\n")
                finally:
                    c.close()
        threading.Thread(target=serve, daemon=True).start()
    while True:
        time.sleep(3600)


main()

# drill mock: rtsp-relay (MediaMTX-style) whose cam04 source has had a flaky
# link for days: it logs jitter / reconnect warnings for cam04 only. Harmless
# for this ticket (the red herring). Listens on :8554 so the video path is up.
import os, signal, socket, sys, threading, time
from mdcommon import procname, write

BD = os.environ.get("MOCKD_BACKDATE")


def ln(t, msg):
    return "%s %s" % (time.strftime("%Y/%m/%d %H:%M:%S", time.localtime(t)), msg)


def flap(t):
    return [ln(t, "WAR [path cam04] [RTSP source] RTP packets lost: 37 (jitter 412ms)"),
            ln(t + 1, "ERR [path cam04] [RTSP source] read tcp 10.50.0.50:41822->"
                      "10.50.1.24:554: i/o timeout"),
            ln(t + 3, "INF [path cam04] [RTSP source] reconnecting in 2s"),
            ln(t + 6, "INF [path cam04] [RTSP source] ready: 1 track (H264)")]


def main():
    procname("mediamtx")
    signal.signal(signal.SIGTERM, lambda *_: (write(ln(time.time(),
                                                       "INF shutting down gracefully")),
                                              sys.exit(0)))
    now = time.time()
    t0 = float(BD) if BD else now
    for m in ("INF MediaMTX v1.9.2", "INF configuration loaded from /config/mediamtx.yml",
              "INF [RTSP] listener opened on :8554 (TCP), :8000 (UDP/RTP), :8001 (UDP/RTCP)"):
        write(ln(t0, m), t0)
    for i in range(1, 7):
        write(ln(t0 + 2, "INF [path cam%02d] [RTSP source] ready: 1 track (H264)" % i), t0 + 2)
    t = t0 + 600
    while t < now - 30:                  # history: cam04 flaps every ~40 min
        for k, m in enumerate(flap(t)):
            write(m, t + k)
        t += 2400
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
                    c.sendall(b"RTSP/1.0 200 OK\r\nCSeq: 1\r\nServer: MediaMTX\r\n\r\n")
                finally:
                    c.close()
        threading.Thread(target=serve, daemon=True).start()
    nxt = time.time() + 20
    while True:
        time.sleep(1)
        if time.time() >= nxt:
            n = time.time()
            for k, m in enumerate(flap(n)):
                write(m, n + k)
            nxt = n + 90


main()

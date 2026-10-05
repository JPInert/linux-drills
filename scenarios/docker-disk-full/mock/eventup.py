# drill mock: event-uploader (ships vehicle events + heartbeats to the cloud).
# Its "stable" tag ships with LOG_LEVEL=debug: it logs every frame-queue poll,
# ~20 kB/s, forever. With no log limit that json-file log grows without end.
import json, os, random, signal, sys, time
from mdcommon import procname, write

LVL = os.environ.get("EU_LOG_LEVEL", "debug").lower()


def ln(level, msg, t=None):
    t = time.time() if t is None else t
    return "%s.%03dZ %s uploader: %s" % (time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)),
                                         int((t % 1) * 1000), level.upper(), msg)


def main():
    procname("event-uploader")
    signal.signal(signal.SIGTERM, lambda *_: (write(ln("info", "shutting down")),
                                              sys.exit(0)))
    write(ln("info", "event-uploader 3.2.0 (stable) starting, log_level=%s" % LVL))
    write(ln("info", "endpoint https://events.edge-cloud.example/v2 (queue /data/queue)"))
    n = 0
    while True:
        time.sleep(0.1)
        n += 1
        if LVL == "debug":
            for cam in range(1, 7):
                write(ln("debug", "poll cam%02d queue=0 inflight=0 last_ack=%d "
                         "backoff_ms=0 frames_seen=%d hb_seq=%d" % (
                             cam, int(time.time()) - random.randint(1, 9),
                             n * 15 + cam, n)))
        if n % 300 == 0:
            write(ln("info", "heartbeat ok seq=%d uploaded=0 pending=0" % n))


main()

id nvr >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin -M nvr
install -d /opt/frame-grabber

cat > /opt/frame-grabber/frame-grabber <<'PY'
#!/usr/bin/python3
import os, sys, time
ROOT = "/var/spool/frames"
body = b"\xff\xd8" + os.urandom(1400) + b"\xff\xd9"
print("frame-grabber: writing thumbnails to %s (one per second, 4 cameras)" % ROOT, flush=True)
n, last_err = 0, 0.0
while True:
    now = time.time()
    lt = time.localtime(now)
    n += 1
    path = "%s/%s/cam%d-%s.jpg" % (ROOT, time.strftime("%Y-%m-%d", lt), n % 4 + 1, time.strftime("%H%M%S", lt))
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(body)
    except OSError as e:
        if now - last_err > 10:
            last_err = now
            print("ERROR frame-grabber: cannot write %s: %s" % (path, e), file=sys.stderr, flush=True)
    time.sleep(1)
PY
chmod 0755 /opt/frame-grabber/frame-grabber
cat > /usr/lib/systemd/system/frame-grabber.service <<'UNIT'
[Unit]
Description=Frame grabber (camera thumbnails for the dashboard)
After=network.target

[Service]
User=nvr
ExecStart=/opt/frame-grabber/frame-grabber
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable frame-grabber >/dev/null 2>&1

# --- fill /var/spool/frames until the filesystem has no inodes left (3000 total, ~12 MB of data)
#     dates are relative to NOW so the scenario never goes stale
python3 - <<'PY'
import errno, os, random, time
ROOT = "/var/spool/frames"
random.seed(4471)
now = int(time.time())
body = b"\xff\xd8" + bytes(random.getrandbits(8) for _ in range(1400)) + b"\xff\xd9"
newest = {}
class Full(Exception): pass
def mk(ts, cam):
    lt = time.localtime(ts)
    d = "%s/%s" % (ROOT, time.strftime("%Y-%m-%d", lt))
    try:
        os.makedirs(d, exist_ok=True)
        p = "%s/cam%d-%s.jpg" % (d, cam, time.strftime("%H%M%S", lt))
        fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        try:
            os.write(fd, body)
        finally:
            os.close(fd)
    except OSError as e:
        if e.errno == errno.ENOSPC:
            raise Full()
        raise
    os.utime(p, (ts, ts))
    newest[d] = max(newest.get(d, 0), ts)
try:
    for i in range(200):                    # CURRENT: the last 20 h (must survive)
        mk(now - 72000 + i * 360, i % 4 + 1)
    for i in range(300):                    # recent: 25 h .. 3.8 days
        mk(now - 90000 - i * 800, i % 4 + 1)
    j = 0
    while True:                             # STALE: 4.2 days and older, until the inodes run out
        mk(now - 362880 - j * 300, j % 4 + 1)
        j += 1
except Full:
    pass
for d, ts in newest.items():                # directory mtimes match their newest file
    os.utime(d, (ts, ts))
open("/var/lib/drill/inode-full.t0", "w").write("%d\n" % int(time.time()))
PY
chown -R nvr:nvr /var/spool/frames
systemctl start frame-grabber
sleep 3

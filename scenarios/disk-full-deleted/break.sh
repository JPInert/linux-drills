id camd >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin -M camd
install -d /opt/cam-poller
install -d -o camd -g camd /var/log/cam-poller
cat > /etc/cam-poller.conf <<'CONF'
# cam-poller: polls the four cameras for status
LOG_FILE=/var/log/cam-poller/poll.log
POLL_INTERVAL=5
# TRACE dumps every raw ONVIF reply into the log. Turned on last week for a camera bug, never turned off.
TRACE=on
CONF

cat > /opt/cam-poller/cam-poller <<'PY'
#!/usr/bin/python3
import os, sys, time
cfg = {}
for line in open("/etc/cam-poller.conf"):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1)
        cfg[k.strip()] = v.strip()
path = cfg.get("LOG_FILE", "/var/log/cam-poller/poll.log")
trace = cfg.get("TRACE", "off").lower() in ("on", "1", "yes", "true")
interval = float(cfg.get("POLL_INTERVAL", "5"))
ts = lambda: time.strftime("%Y-%m-%d %H:%M:%S")
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)     # opened once, held for life
print("cam-poller: polling 4 cameras every %ss, TRACE=%s, log=%s" % (interval, "on" if trace else "off", path), flush=True)
n, last_hb, last_err = 0, 0.0, 0.0
LINE = "%s TRACE onvif: cam-%02d GetDeviceInformation reply=<s:Envelope xmlns:s=\"http://www.w3.org/2003/05/soap-envelope\"><s:Body><tds:Manufacturer>Dahua</tds:Manufacturer><tds:SerialNumber>4K0A%06d</tds:SerialNumber></s:Body></s:Envelope>\n"
while True:
    now = time.time()
    out = ""
    if trace:
        t = ts()
        out = "".join(LINE % (t, (n + k) % 4 + 1, n + k) for k in range(125))
        n += 125
    if now - last_hb >= interval:
        last_hb = now
        out += "%s INFO  poll: cams=4 online=4 rtt_ms=%d\n" % (ts(), 12 + int(now) % 5)
    try:
        if out:
            os.write(fd, out.encode())
    except OSError as e:
        if now - last_err > 10:
            last_err = now
            print("ERROR poll: cannot write %s: %s" % (path, e), file=sys.stderr, flush=True)
    time.sleep(0.05 if trace else 0.5)
PY
chmod 0755 /opt/cam-poller/cam-poller
cat > /usr/lib/systemd/system/cam-poller.service <<'UNIT'
[Unit]
Description=Camera status poller
After=network.target

[Service]
User=camd
ExecStart=/opt/cam-poller/cam-poller
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

# legitimate old logs, so `du` has something honest to show
install -d /var/log/nvr
head -c 1200000 /dev/urandom | gzip -c > /var/log/nvr/recorder.log.1.gz
head -c 900000  /dev/urandom | gzip -c > /var/log/nvr/recorder.log.2.gz
yes '2026-09-23 03:12:44 INFO recorder: segment closed cam=cam-02 len=300s bytes=48211044' | head -c 400000 > /var/log/nvr/recorder.log

systemctl daemon-reload
systemctl enable --now cam-poller >/dev/null 2>&1
for i in $(seq 1 20); do [ -s /var/log/cam-poller/poll.log ] && break; sleep 0.5; done
# the "huge log": grow it while the daemon holds it open, then someone deletes it
yes '2026-09-22 22:41:07 TRACE onvif: cam-03 GetDeviceInformation reply=<s:Envelope><s:Body>...</s:Body></s:Envelope>' | head -c 43000000 >> /var/log/cam-poller/poll.log || true
rm -f /var/log/cam-poller/poll.log
# the daemon keeps writing into the deleted file until the filesystem is full
for i in $(seq 1 90); do
  avail=$(df -B1 --output=avail /var/log | tail -1)
  [ "${avail:-0}" -lt 200000 ] && break
  sleep 0.5
done
sleep 1

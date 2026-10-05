. /drill-lab/baseline.sh
# the site's stream-ingest service (pulls camera1's RTSP stream for vehicle counting) still holds the
# password the site rotated to; last night's camera firmware update reset camera1 to the install-sheet value
cat >> /home/tech/install-sheet.txt <<'SHEET'

  camera1 stream   rtsp://10.50.1.31:554/Streaming/Channels/101   (main, 1080p H.264)
                   user nvr   password HR-cam1-4471   (install value)
  ingest service   stream-ingest.service   config /etc/stream-ingest/ingest.conf
SHEET

id ingest >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin -M ingest
install -d /opt/stream-ingest /etc/stream-ingest
cat > /opt/stream-ingest/ingest.py <<'PY'
#!/usr/bin/python3
"""stream-ingest: keep camera1's RTSP session described for the vehicle-count pipeline."""
import base64, json, os, socket, stat, sys, time

CONF = "/etc/stream-ingest/ingest.conf"
STATUS = "/run/stream-ingest/status"


def log(msg):
    print(msg, flush=True)


def load():
    st = os.stat(CONF)
    if st.st_mode & (stat.S_IROTH | stat.S_IWOTH | stat.S_IWGRP):
        log("refusing %s: mode %o is readable or writable beyond root:ingest (it holds the camera password)"
            % (CONF, stat.S_IMODE(st.st_mode)))
        sys.exit(78)
    cfg = {}
    for line in open(CONF):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            cfg[k.strip()] = v.strip().strip('"')
    return cfg


def describe(url, user, pw, cseq):
    hostport = url.split("://", 1)[1].split("/", 1)[0]
    host, _, port = hostport.partition(":")
    req = "DESCRIBE %s RTSP/1.0\r\nCSeq: %d\r\nAccept: application/sdp\r\nUser-Agent: stream-ingest/1.3\r\n" % (url, cseq)
    if user:
        req += "Authorization: Basic %s\r\n" % base64.b64encode(("%s:%s" % (user, pw)).encode()).decode()
    with socket.create_connection((host, int(port or 554)), timeout=4) as s:
        s.sendall((req + "\r\n").encode())
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
    return data.split(b"\r\n", 1)[0].decode("latin-1") or "(empty reply)"


def main():
    cfg = load()
    url, user, pw = cfg.get("CAMERA_URL", ""), cfg.get("CAMERA_USER", ""), cfg.get("CAMERA_PASS", "")
    every = float(cfg.get("POLL_SECONDS", "3"))
    name = cfg.get("CAMERA_NAME", "camera1")
    log("stream-ingest 1.3 starting: %s %s user=%s" % (name, url, user))
    cseq = 0
    while True:
        cseq += 1
        try:
            status = describe(url, user, pw, cseq)
        except OSError as e:
            status = "connect failed: %s" % e
        up = status.startswith("RTSP/1.0 200")
        log("%s: DESCRIBE %s -> %s" % (name, url, status))
        if not up:
            log("%s: stream unavailable, retry in %gs" % (name, every))
        tmp = STATUS + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"camera": name, "url": url, "last": status, "stream": "up" if up else "unavailable",
                       "at": time.strftime("%Y-%m-%dT%H:%M:%S%z")}, f)
            f.write("\n")
        os.replace(tmp, STATUS)
        time.sleep(every)


main()
PY
chmod 0755 /opt/stream-ingest/ingest.py

cat > /etc/stream-ingest/ingest.conf <<'CONF'
# stream-ingest: camera1 main stream for vehicle counting (Northgate Garage)
# credentials rotated by site IT 2025-03 (ticket HR-2291)
CAMERA_NAME=camera1
CAMERA_URL=rtsp://10.50.1.31:554/Streaming/Channels/101
CAMERA_USER=nvr
CAMERA_PASS=Nvr2024-HR09
POLL_SECONDS=3
# older camera firmware used rtsp://<cam>/h264/ch1/main/av_stream
CONF
chown root:ingest /etc/stream-ingest/ingest.conf; chmod 0640 /etc/stream-ingest/ingest.conf

cat > /etc/systemd/system/stream-ingest.service <<'UNIT'
[Unit]
Description=Stream ingest (camera RTSP -> vehicle-count pipeline)
After=network-online.target

[Service]
ExecStart=/usr/bin/python3 /opt/stream-ingest/ingest.py
User=ingest
Group=ingest
RuntimeDirectory=stream-ingest
RuntimeDirectoryPreserve=yes
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now stream-ingest >/dev/null 2>&1
for _ in $(seq 1 30); do grep -q '401' /run/stream-ingest/status 2>/dev/null && break; sleep 0.5; done
grep -q '"last": "RTSP/1.0 401' /run/stream-ingest/status

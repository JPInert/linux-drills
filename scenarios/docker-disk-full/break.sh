# docker-disk-full: /var/lib/docker (its own small filesystem here) is full.
# event-uploader:stable logs at debug level into an unbounded json-file log,
# old vehicle-count images and dangling event-uploader images pile up, so the
# nightly pull of vehicle-count 2.5.0 dies "no space left on device".
/usr/local/lib/drill/lived-in >/dev/null 2>&1
/usr/local/lib/drill/docker-install

W=/usr/local/lib/mock-docker
install -m 0644 /drill/mock/common.py $W/mdcommon.py
for k in vehiclecount25 rtsprelayj eventup; do
  install -d -m 0755 $W/$k
  install -m 0644 /drill/mock/$k.py $W/$k/__main__.py
done
FDENV='"env": ["PATH=/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", "NVIDIA_VISIBLE_DEVICES=all", "NVIDIA_DRIVER_CAPABILITIES=compute,utility", "CUDA_VERSION=12.2.0"'
cat > /etc/mock-docker/images.d/edge.json <<JSON
{
  "nvidia/cuda:12.2.0-base-ubuntu22.04": null,
  "registry.local/edge/vehicle-count:2.5.0": {"kind": "vehiclecount25", "disk": "25.1MB",
      "age": 345600, "remote": true, "workdir": "/app", $FDENV, "FD_VERSION=2.5.0"]},
  "registry.local/edge/vehicle-count:2.4.1": {"kind": "vehiclecount25", "disk": "24.2MB",
      "age": 3456000, "workdir": "/app", $FDENV, "FD_VERSION=2.4.1"]},
  "registry.local/edge/vehicle-count:2.4.0": {"kind": "vehiclecount25", "disk": "24.1MB",
      "age": 6048000, "workdir": "/app", $FDENV, "FD_VERSION=2.4.0"]},
  "registry.local/edge/vehicle-count:2.3.9": {"kind": "vehiclecount25", "disk": "23.4MB",
      "age": 9072000, "workdir": "/app", $FDENV, "FD_VERSION=2.3.9"]},
  "registry.local/edge/vehicle-count:2.3.8": {"kind": "vehiclecount25", "disk": "23.2MB",
      "age": 11232000, "workdir": "/app", $FDENV, "FD_VERSION=2.3.8"]},
  "registry.local/edge/rtsp-relay:1.9.2": {"kind": "rtsprelayj", "disk": "4.8MB",
      "age": 5529600, "cmd": ["python3", "-m", "rtsprelayj"]},
  "registry.local/edge/event-uploader:stable": {"kind": "eventup", "disk": "9.3MB",
      "age": 604800, "cmd": ["python3", "-m", "eventup"]},
  "sha256:7d1c0b9e44a2f1e38c5a6b7d9e0f1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b": {
      "kind": "eventup", "disk": "9.3MB", "age": 1209600, "dangling": true},
  "sha256:a93e5f7c2b1d4e6f8a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f": {
      "kind": "eventup", "disk": "9.2MB", "age": 1814400, "dangling": true},
  "sha256:4b8f2e6a1c3d5e7f9a0b2c4d6e8f0a1b3c5d7e9f1a2b4c6d8e0f2a4b6c8d0e1f": {
      "kind": "eventup", "disk": "9.2MB", "age": 2419200, "dangling": true}
}
JSON
# the images "already here" really occupy their bytes
for r in registry.local/edge/vehicle-count:2.4.1 registry.local/edge/vehicle-count:2.4.0 \
         registry.local/edge/vehicle-count:2.3.9 registry.local/edge/vehicle-count:2.3.8 \
         registry.local/edge/rtsp-relay:1.9.2 registry.local/edge/event-uploader:stable; do
  docker pull -q "$r" >/dev/null
done
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
from importlib.machinery import SourceFileLoader
d = SourceFileLoader("mockdocker", "/usr/local/bin/docker").load_module()
for ref, img in d.IMAGES.items():
    if img.get("dangling"):
        d.materialise(img)
PY

# --- the stack
F=/opt/edge
install -d -m 0755 $F /etc/vehicle-count /var/lib/vehicle-count /var/lib/event-uploader \
  /opt/vehicle-count/models/v7
printf 'fall-pose 7.2 fp32\nTensorRT engine (drill stand-in)\n' > /opt/vehicle-count/models/v7/fall-pose-v7.engine
cat > /etc/vehicle-count/mediamtx.yml <<'YML'
rtspAddress: :8554
paths:
  cam01: {source: rtsp://10.50.1.21:554/stream1}
  cam02: {source: rtsp://10.50.1.22:554/stream1}
  cam03: {source: rtsp://10.50.1.23:554/stream1}
  cam04: {source: rtsp://10.50.1.24:554/stream1}
  cam05: {source: rtsp://10.50.1.25:554/stream1}
  cam06: {source: rtsp://10.50.1.26:554/stream1}
YML
cat > $F/compose.yaml <<'YML'
# edge stack: vehicle counting, video relay, event upload
name: edge

services:
  rtsp-relay:
    image: registry.local/edge/rtsp-relay:1.9.2
    container_name: rtsp-relay
    restart: unless-stopped
    network_mode: host
    volumes:
      - /etc/vehicle-count/mediamtx.yml:/config/mediamtx.yml:ro

  vehicle-count:
    image: registry.local/edge/vehicle-count:2.4.1
    container_name: vehicle-count
    restart: unless-stopped
    network_mode: host
    depends_on:
      - rtsp-relay
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    environment:
      - FD_DEVICE=cuda
      - FD_MODEL=/models/fall-pose-v7.engine
      - FD_RTSP_SOURCE=rtsp://127.0.0.1:8554
    volumes:
      - /opt/vehicle-count/models/v7:/models:ro
      - /var/lib/vehicle-count:/data

  event-uploader:
    image: registry.local/edge/event-uploader:stable
    container_name: event-uploader
    restart: unless-stopped
    network_mode: host
    volumes:
      - /var/lib/event-uploader:/data
YML
chmod 0644 $F/compose.yaml

# --- recordings: their own disk, not full (the site lead's theory)
install -d -m 0755 /srv/nvr/recordings
python3 - <<'PY'
import os, time
base = "/srv/nvr/recordings"
now = time.time()
for day in range(6, -1, -1):
    d = os.path.join(base, time.strftime("%Y-%m-%d", time.localtime(now - day * 86400)))
    os.makedirs(d, exist_ok=True)
    for cam in range(1, 7):
        fn = os.path.join(d, "cam%02d_events.mp4" % cam)
        with open(fn, "wb") as f:
            f.write(b"\0" * (900 * 1024))
        os.utime(fn, (now - day * 86400, now - day * 86400))
PY
find /srv/nvr/recordings -type f | wc -l > /var/lib/drill/.nvr-files
chmod 0600 /var/lib/drill/.nvr-files

# the updater's log: three nights of failed pulls
u() { printf '%s %s\n' "$(date -d "$1" '+%F %T')" "$2"; }
{
  for n in 3 2 1; do
    u "$n days ago 03:00:04" 'edge-update 1.5.0: bundle vehicle-count 2.5.0 available (installed 2.4.1)'
    u "$n days ago 03:00:05" 'pulling registry.local/edge/vehicle-count:2.5.0'
    u "$n days ago 03:01:37" 'ERROR docker pull: failed to register layer: write /var/lib/docker/overlay2/.../usr/lib/x86_64-linux-gnu/libcudnn_ops.so.8.9.7: no space left on device'
    u "$n days ago 03:01:37" 'update aborted, vehicle-count stays on 2.4.1 (rollback image 2.4.0 kept)'
  done
} > /var/log/edge-update.log

cd $F
MOCK_DOCKER_BACKDATE=rtsp-relay=5184000,vehicle-count=3456000,event-uploader=604800 \
  docker compose up -d >/dev/null 2>&1
for _ in $(seq 1 40); do docker ps --format '{{.Names}}' | grep -qx event-uploader && break; sleep 0.25; done

# a week of debug logging, until the filesystem is full
LOG=$(docker inspect event-uploader | grep '"LogPath"' | cut -d'"' -f4)
python3 - "$LOG" <<'PY'
import json, os, sys, time
log = sys.argv[1]
v = os.statvfs("/var/lib/docker")
def rec(t, cam):
    msg = ("%s.%03dZ DEBUG uploader: poll cam%02d queue=0 inflight=0 last_ack=%d "
           "backoff_ms=0 frames_seen=%d hb_seq=%d\n" % (
               time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)), 0, cam, int(t) - 3,
               int(t) % 100000 * 15 + cam, int(t) % 100000))
    return json.dumps({"log": msg, "stream": "stdout", "time": time.strftime(
        "%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".000000000Z"}) + "\n"
now = time.time()
per = sum(len(rec(now, c)) for c in range(1, 7))
est = v.f_bavail * v.f_frsize / per             # batches of 6 lines until full
step = 7 * 86400 / max(est, 1)
t = now - 7 * 86400
try:
    with open(log, "a") as f:
        while True:
            for cam in range(1, 7):
                f.write(rec(min(t, now - 20), cam))
            t += step
except OSError:
    pass
PY
df --output=pcent /var/lib/docker | tail -1 | grep -q 100%
docker ps --format '{{.Names}}' | grep -qx vehicle-count

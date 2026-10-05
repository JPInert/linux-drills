# docker-analytics: vehicle-count runs in Docker Compose; the vendor's 2.4.1 compose
# template dropped the GPU reservation, so the container silently runs on CPU.
# There is no real Docker in the drill box: the shared mock engine + this stack's workloads.
/usr/local/lib/drill/docker-install
install -d -m 0755 /usr/local/lib/mock-docker/vehiclecount /usr/local/lib/mock-docker/rtsprelay
install -m 0644 /drill/mock/vehiclecount.py /usr/local/lib/mock-docker/vehiclecount/__main__.py
install -m 0644 /drill/mock/rtsprelay.py /usr/local/lib/mock-docker/rtsprelay/__main__.py

# --- the stack
install -d -m 0755 /opt/vehicle-count/models /etc/vehicle-count /var/lib/vehicle-count
: > /opt/vehicle-count/models/fall-pose-v7.engine
: > /opt/vehicle-count/models/fall-pose-v7.onnx
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

# the compose file as it was on 2.3.8 (the updater keeps this copy) ...
cat > /opt/vehicle-count/compose.yaml.2.3.8.bak <<'YML'
# vehicle-count edge stack
name: vehicle-count

services:
  rtsp-relay:
    image: registry.local/edge/rtsp-relay:1.9.2
    container_name: rtsp-relay
    restart: unless-stopped
    network_mode: host
    volumes:
      - /etc/vehicle-count/mediamtx.yml:/config/mediamtx.yml:ro

  vehicle-count:
    image: registry.local/edge/vehicle-count:2.3.8
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
      - FD_ALERT_URL=https://alerts.facility.lan/api/v1/events
    volumes:
      - /opt/vehicle-count/models:/models:ro
      - /var/lib/vehicle-count:/data
YML
# ... and the 2.4.1 bundle template it wrote over it: same stack, no GPU stanza
cat > /opt/vehicle-count/compose.yaml <<'YML'
# vehicle-count edge stack (edge-update 2.4.1 bundle template)
name: vehicle-count

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
    environment:
      - FD_DEVICE=cuda
      - FD_MODEL=/models/fall-pose-v7.engine
      - FD_RTSP_SOURCE=rtsp://127.0.0.1:8554
      - FD_ALERT_URL=https://alerts.facility.lan/api/v1/events
    volumes:
      - /opt/vehicle-count/models:/models:ro
      - /var/lib/vehicle-count:/data
YML
chmod 0644 /opt/vehicle-count/compose.yaml /opt/vehicle-count/compose.yaml.2.3.8.bak
touch -d '41 days ago' /opt/vehicle-count/compose.yaml.2.3.8.bak
touch -d '14 hours ago' /opt/vehicle-count/compose.yaml

# the updater's own log (times relative to now: it ran overnight)
u() { printf '%s %s\n' "$(date -d "$1" '+%F %T')" "$2"; }
{
  u '14 hours ago 10 minutes ago' 'edge-update 1.4.0: checking channel stable for edge-nvr-03'
  u '14 hours ago 10 minutes ago' 'bundle vehicle-count 2.4.1 available (installed 2.3.8)'
  u '14 hours ago 3 minutes ago'  'pulled registry.local/edge/vehicle-count:2.4.1'
  u '14 hours ago 2 minutes ago'  'backed up /opt/vehicle-count/compose.yaml -> compose.yaml.2.3.8.bak'
  u '14 hours ago 2 minutes ago'  'wrote /opt/vehicle-count/compose.yaml from bundle template'
  u '14 hours ago'                'docker compose up -d: vehicle-count recreated'
  u '14 hours ago -15 seconds'    'health: container vehicle-count is running  OK'
  u '14 hours ago -16 seconds'    'update complete'
} > /var/log/edge-update.log

# bring the stack up the way the updater did; the relay has been up for 9 days
MOCK_DOCKER_BACKDATE=rtsp-relay=777600,vehicle-count=50400 \
  docker compose -f /opt/vehicle-count/compose.yaml up -d >/dev/null 2>&1
for _ in $(seq 1 40); do
  docker logs vehicle-count 2>/dev/null | grep -q 'falling back to CPU' && break; sleep 0.25
done
docker logs vehicle-count 2>/dev/null | grep -q 'falling back to CPU'
docker ps --format '{{.Names}}' | grep -qx rtsp-relay

# chain-docker-crashloop: the 03:00 vendor update (vehicle-count 2.5.0 + model
# fall-pose 8.1) moved models into versioned dirs, but its compose template
# names the model file without the "-fp16" the package actually ships. The
# detector can't open its model, exits 1, and restart: unless-stopped turns
# that into a crash loop. Video (rtsp-relay) is fine; cam04's link is flaky.
/usr/local/lib/drill/lived-in >/dev/null 2>&1
/usr/local/lib/drill/docker-install

W=/usr/local/lib/mock-docker
install -m 0644 /drill/mock/common.py $W/mdcommon.py
for k in vehiclecount25 rtsprelayj; do
  install -d -m 0755 $W/$k
  install -m 0644 /drill/mock/$k.py $W/$k/__main__.py
done
cat > /etc/mock-docker/images.d/vehicle-count.json <<'JSON'
{
  "registry.local/edge/vehicle-count:2.5.0": {
    "kind": "vehiclecount25", "size": "6.34GB", "age": 172800, "workdir": "/app",
    "cmd": ["python3", "-m", "vehiclecount25"],
    "env": ["PATH=/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "NVIDIA_VISIBLE_DEVICES=all", "NVIDIA_DRIVER_CAPABILITIES=compute,utility",
            "CUDA_VERSION=12.2.0", "FD_VERSION=2.5.0"]},
  "registry.local/edge/vehicle-count:2.4.1": {
    "kind": "vehiclecount25", "size": "6.21GB", "age": 3456000, "workdir": "/app",
    "cmd": ["python3", "-m", "vehiclecount25"],
    "env": ["PATH=/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "NVIDIA_VISIBLE_DEVICES=all", "NVIDIA_DRIVER_CAPABILITIES=compute,utility",
            "CUDA_VERSION=12.2.0", "FD_VERSION=2.4.1"]},
  "registry.local/edge/rtsp-relay:1.9.2": {
    "kind": "rtsprelayj", "size": "48.3MB", "age": 5529600, "workdir": "/",
    "cmd": ["python3", "-m", "rtsprelayj"]}
}
JSON

# --- the stack on disk
F=/opt/vehicle-count
install -d -m 0755 $F $F/models $F/models/v7 $F/models/v8.1 /etc/vehicle-count /var/lib/vehicle-count
printf 'fall-pose 7.2 fp32\nTensorRT engine (drill stand-in)\n' > $F/models/v7/fall-pose-v7.engine
printf 'fall-pose 7.2 fp32\nONNX (drill stand-in)\n' > $F/models/v7/fall-pose-v7.onnx
printf 'fall-pose 8.1 fp16\nTensorRT engine (drill stand-in)\n' > $F/models/v8.1/fall-pose-v8.1-fp16.engine
printf 'fall-pose 8.1 fp16\nONNX (drill stand-in)\n' > $F/models/v8.1/fall-pose-v8.1-fp16.onnx
cat > $F/models/v8.1/manifest.json <<'JSON'
{
  "model": "fall-pose",
  "version": "8.1",
  "precision": "fp16",
  "engine": "fall-pose-v8.1-fp16.engine",
  "onnx": "fall-pose-v8.1-fp16.onnx",
  "min_runtime": "vehicle-count >= 2.5.0"
}
JSON
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

svc_relay='  rtsp-relay:
    image: registry.local/edge/rtsp-relay:1.9.2
    container_name: rtsp-relay
    restart: unless-stopped
    network_mode: host
    volumes:
      - /etc/vehicle-count/mediamtx.yml:/config/mediamtx.yml:ro
'
gpu='    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
'
# the 2.4.1 compose file, as the updater backed it up ...
cat > $F/compose.yaml.2.4.1.bak <<YML
# vehicle-count edge stack (edge-update 2.4.1 bundle template)
name: vehicle-count

services:
$svc_relay
  vehicle-count:
    image: registry.local/edge/vehicle-count:2.4.1
    container_name: vehicle-count
    restart: unless-stopped
    network_mode: host
    depends_on:
      - rtsp-relay
$gpu    environment:
      - FD_DEVICE=cuda
      - FD_MODEL=/models/fall-pose-v7.engine
      - FD_RTSP_SOURCE=rtsp://127.0.0.1:8554
      - FD_ALERT_URL=https://alerts.facility.lan/api/v1/events
    volumes:
      - /opt/vehicle-count/models:/models:ro
      - /var/lib/vehicle-count:/data
YML
# ... and the 2.5.0 template it wrote: versioned model dir, model name without -fp16
cat > $F/compose.yaml <<YML
# vehicle-count edge stack (edge-update 2.5.0 bundle template)
name: vehicle-count

services:
$svc_relay
  vehicle-count:
    image: registry.local/edge/vehicle-count:2.5.0
    container_name: vehicle-count
    restart: unless-stopped
    network_mode: host
    depends_on:
      - rtsp-relay
$gpu    environment:
      - FD_DEVICE=cuda
      - FD_MODEL=/models/fall-pose-v8.1.engine
      - FD_RTSP_SOURCE=rtsp://127.0.0.1:8554
      - FD_ALERT_URL=https://alerts.facility.lan/api/v1/events
    volumes:
      - /opt/vehicle-count/models/v8.1:/models:ro
      - /var/lib/vehicle-count:/data
YML
# old layout: models sat directly in models/; the update moved them into v7/
chmod 0644 $F/compose.yaml $F/compose.yaml.2.4.1.bak

# when the update ran: the most recent 03:00
up=$(date -d 'today 03:00:05' +%s); [ "$up" -gt "$(date +%s)" ] && up=$(date -d 'yesterday 03:00:05' +%s)
T() { date -d "@$(( up + $1 ))" '+%F %T'; }
{
  echo "$(T 0) edge-update 1.5.0: checking channel stable for edge-nvr-03"
  echo "$(T 2) bundle vehicle-count 2.5.0 available (installed 2.4.1)"
  echo "$(T 2) model fall-pose 8.1 available (installed 7.2)"
  echo "$(T 88) pulled registry.local/edge/vehicle-count:2.5.0"
  echo "$(T 95) models are now versioned: moved fall-pose 7.2 to /opt/vehicle-count/models/v7/"
  echo "$(T 97) unpacked fall-pose 8.1 to /opt/vehicle-count/models/v8.1/ (see manifest.json)"
  echo "$(T 98) backed up /opt/vehicle-count/compose.yaml -> compose.yaml.2.4.1.bak"
  echo "$(T 98) wrote /opt/vehicle-count/compose.yaml from bundle template"
  echo "$(T 99) docker compose up -d: vehicle-count recreated"
  echo "$(T 114) health: container vehicle-count state=restarting (health gate disabled on channel stable)"
  echo "$(T 114) update complete"
} > /var/log/edge-update.log
touch -d "@$(( up + 98 ))" $F/compose.yaml
touch -d "@$(( up - 3456000 ))" $F/compose.yaml.2.4.1.bak

now=$(date +%s); since=$(( now - up - 99 ))
cd $F
MOCK_DOCKER_BACKDATE=rtsp-relay=777600,vehicle-count=$since \
MOCK_DOCKER_RESTARTS=vehicle-count=$(( since / 60 )) \
  docker compose up -d >/dev/null 2>&1 || true
for _ in $(seq 1 60); do
  docker ps -a 2>/dev/null | grep -q 'Restarting (1)' && break; sleep 0.25
done
docker ps -a | grep vehicle-count | grep -q 'Restarting (1)'
docker ps --format '{{.Names}}' | grep -qx rtsp-relay

# on the GPU, but outside compose: the next `compose up` / vendor update undoes it
docker rm -f vehicle-count
docker run -d --name vehicle-count --gpus all --restart unless-stopped --network host \
  -e FD_DEVICE=cuda -e FD_MODEL=/models/fall-pose-v7.engine \
  -e FD_RTSP_SOURCE=rtsp://127.0.0.1:8554 \
  -e FD_ALERT_URL=https://alerts.facility.lan/api/v1/events \
  -v /opt/vehicle-count/models:/models:ro -v /var/lib/vehicle-count:/data \
  registry.local/edge/vehicle-count:2.4.1
sleep 2

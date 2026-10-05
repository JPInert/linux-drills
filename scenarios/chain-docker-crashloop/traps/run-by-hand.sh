# right model, but outside compose: the next update or compose up undoes it
docker rm -f vehicle-count
docker run -d --name vehicle-count --gpus all --restart unless-stopped --network host \
  -e FD_DEVICE=cuda -e FD_MODEL=/models/fall-pose-v8.1-fp16.engine \
  -e FD_RTSP_SOURCE=rtsp://127.0.0.1:8554 \
  -v /opt/vehicle-count/models/v8.1:/models:ro -v /var/lib/vehicle-count:/data \
  registry.local/edge/vehicle-count:2.5.0
sleep 3

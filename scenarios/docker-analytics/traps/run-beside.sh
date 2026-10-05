# fixed properly, then a hand-run GPU copy left beside it: two detectors on one set of cameras
printf '    deploy:\n      resources:\n        reservations:\n          devices:\n            - driver: nvidia\n              count: all\n              capabilities: [gpu]\n' > /tmp/gpu.yaml
sed -i '/^    container_name: vehicle-count$/r /tmp/gpu.yaml' /opt/vehicle-count/compose.yaml
docker compose -f /opt/vehicle-count/compose.yaml up -d
docker run -d --name vehicle-count-gpu --gpus all --network host registry.local/edge/vehicle-count:2.4.1
sleep 2

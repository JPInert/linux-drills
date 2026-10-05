# right edit, wrong verb: the stanza is back in the file but the container was only restarted
printf '    deploy:\n      resources:\n        reservations:\n          devices:\n            - driver: nvidia\n              count: all\n              capabilities: [gpu]\n' > /tmp/gpu.yaml
sed -i '/^    container_name: vehicle-count$/r /tmp/gpu.yaml' /opt/vehicle-count/compose.yaml
docker restart vehicle-count
sleep 2

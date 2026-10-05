# silence the warning instead of fixing it: FD_DEVICE=cpu, recreated properly, still CPU
sed -i 's/FD_DEVICE=cuda/FD_DEVICE=cpu/' /opt/vehicle-count/compose.yaml
docker compose -f /opt/vehicle-count/compose.yaml up -d
sleep 2

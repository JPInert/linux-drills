# stop the loop instead of fixing it: restart "no" leaves it dead (and dead after a reboot)
sed -i '/container_name: vehicle-count/{n;s/restart: unless-stopped/restart: "no"/}' /opt/vehicle-count/compose.yaml
cd /opt/vehicle-count && docker compose up -d
sleep 3

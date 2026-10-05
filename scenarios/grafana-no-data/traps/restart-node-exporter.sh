# fix the red herring: the host's node exporter was never the problem
systemctl restart prometheus-node-exporter
cd /opt/monitoring && docker compose restart prometheus
sleep 2

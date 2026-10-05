set -e
F=/opt/monitoring/grafana/provisioning/datasources/prometheus.yaml
# point the datasource at Prometheus itself (this site has no prom-auth on :9091)
sudo sed -i 's#url: http://localhost:9091#url: http://localhost:9090#' "$F"
# Grafana reads provisioning only at start
cd /opt/monitoring
sudo docker compose restart grafana
sleep 2

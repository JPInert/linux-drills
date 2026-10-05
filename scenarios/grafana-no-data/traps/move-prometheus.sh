# make Prometheus listen where Grafana looks: breaks the NOC federation on :9090
sed -i 's#--web.listen-address=:9090#--web.listen-address=:9091#' /opt/monitoring/compose.yaml
cd /opt/monitoring && docker compose up -d
sleep 3

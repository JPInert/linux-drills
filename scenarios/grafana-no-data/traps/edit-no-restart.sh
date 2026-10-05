# right edit, but Grafana only reads provisioning when it starts
sed -i 's#localhost:9091#localhost:9090#' /opt/monitoring/grafana/provisioning/datasources/prometheus.yaml
sleep 2

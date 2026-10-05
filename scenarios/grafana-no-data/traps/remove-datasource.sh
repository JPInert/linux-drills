# "the new datasource is broken, delete it": no errors, and no data either
rm -f /opt/monitoring/grafana/provisioning/datasources/prometheus.yaml
cd /opt/monitoring && docker compose restart grafana
sleep 2

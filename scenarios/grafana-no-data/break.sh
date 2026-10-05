# grafana-no-data: the monitoring bundle 2.0 update rewrote Grafana's datasource
# provisioning to point at a "prom-auth" proxy on :9091 that this site never
# deploys. Prometheus is fine on :9090; every panel query is refused.
/usr/local/lib/drill/lived-in >/dev/null 2>&1
/usr/local/lib/drill/docker-install

W=/usr/local/lib/mock-docker
install -m 0644 /drill/mock/common.py $W/mdcommon.py
for k in grafana prometheus; do
  install -d -m 0755 $W/$k
  install -m 0644 /drill/mock/$k.py $W/$k/__main__.py
done
cat > /etc/mock-docker/images.d/monitoring.json <<'JSON'
{
  "grafana/grafana:11.2.0":   {"kind": "grafana", "size": "468MB", "age": 2592000,
                               "workdir": "/usr/share/grafana"},
  "grafana/grafana:10.4.2":   {"kind": "grafana", "size": "421MB", "age": 13737600,
                               "workdir": "/usr/share/grafana"},
  "prom/prometheus:v2.54.1":  {"kind": "prometheus", "size": "274MB", "age": 3024000,
                               "workdir": "/prometheus"},
  "prom/prometheus:v2.51.2":  {"kind": "prometheus", "size": "262MB", "age": 13737600,
                               "workdir": "/prometheus"}
}
JSON

M=/opt/monitoring
install -d -m 0755 $M $M/prometheus $M/grafana/provisioning/datasources \
  $M/grafana/provisioning/dashboards $M/grafana/dashboards /var/lib/prometheus-data \
  /var/lib/grafana
cat > $M/compose.yaml <<'YML'
# edge monitoring stack (monitoring bundle 2.0)
name: monitoring

services:
  prometheus:
    image: prom/prometheus:v2.54.1
    container_name: prometheus
    restart: unless-stopped
    network_mode: host
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --web.listen-address=:9090
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - /var/lib/prometheus-data:/prometheus

  grafana:
    image: grafana/grafana:11.2.0
    container_name: grafana
    restart: unless-stopped
    network_mode: host
    depends_on:
      - prometheus
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=Northgate-NOC
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
      - /var/lib/grafana:/var/lib/grafana
YML
cat > $M/prometheus/prometheus.yml <<'YML'
global:
  scrape_interval: 15s
  external_labels:
    site: northgate

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ['localhost:9090']
  - job_name: node
    static_configs:
      - targets: ['localhost:9100']
YML
cat > $M/grafana/provisioning/datasources/prometheus.yaml <<'YML'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    uid: prometheus-edge
    access: proxy
    url: http://localhost:9091
    isDefault: true
    editable: false
    jsonData:
      timeInterval: 15s
      httpMethod: POST
YML
cat > $M/grafana/provisioning/dashboards/edge.yaml <<'YML'
apiVersion: 1

providers:
  - name: edge
    folder: Northgate Garage
    type: file
    options:
      path: /var/lib/grafana/dashboards
YML
printf '{"uid": "edge-box-health", "title": "Northgate Garage - Edge Box Health", "panels": [{"id": 2, "title": "Load", "targets": [{"expr": "node_load1", "datasource": {"uid": "prometheus-edge"}}]}]}\n' \
  > $M/grafana/dashboards/edge-box-health.json
cat > $M/CHANGELOG.md <<'MD'
# edge monitoring bundle

## 2.0
- Prometheus 2.54.1, Grafana 11.2.0; all services on host networking
- Grafana datasource now goes through prom-auth (basic auth in front of
  Prometheus) on :9091. prom-auth is deployed only on sites with the
  "prom-auth" profile; other sites keep Prometheus on :9090.
- NOC federation keeps scraping Prometheus directly on :9090

## 1.6
- Grafana 10.4.2, Prometheus 2.51.2, datasource http://localhost:9090
MD
chmod -R a+rX $M

# the updater's log: it ran yesterday afternoon
u() { printf '%s %s\n' "$(date -d "$1" '+%F %T')" "$2"; }
{
  u 'yesterday 14:02:10' 'edge-update 1.5.0: bundle monitoring 2.0 available (installed 1.6)'
  u 'yesterday 14:03:31' 'pulled grafana/grafana:11.2.0, prom/prometheus:v2.54.1'
  u 'yesterday 14:03:33' 'wrote /opt/monitoring/compose.yaml from bundle template'
  u 'yesterday 14:03:33' 'wrote /opt/monitoring/grafana/provisioning/datasources/prometheus.yaml'
  u 'yesterday 14:03:34' 'profile northgate: prom-auth not enabled, skipping prom-auth'
  u 'yesterday 14:03:41' 'docker compose up -d: prometheus, grafana recreated'
  u 'yesterday 14:03:52' 'health: http://localhost:3000/api/health 200  OK'
  u 'yesterday 14:03:52' 'update complete'
} > /var/log/edge-update.log
touch -d 'yesterday 14:03:33' $M/compose.yaml $M/grafana/provisioning/datasources/prometheus.yaml

cd $M
MOCK_DOCKER_BACKDATE=prometheus=$(( $(date +%s) - $(date -d 'yesterday 14:03:41' +%s) )),grafana=$(( $(date +%s) - $(date -d 'yesterday 14:03:41' +%s) )) \
  docker compose up -d >/dev/null 2>&1
for _ in $(seq 1 40); do
  grep -q '"ok": false' /run/.drill-grafana-state 2>/dev/null && \
    grep -q 'refused' /run/.drill-grafana-state && break
  sleep 0.25
done
grep -q 'connection refused' /run/.drill-grafana-state
(exec 3<>/dev/tcp/127.0.0.1/9090) 2>/dev/null

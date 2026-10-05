# right daemon.json, but log-opts only apply to containers created AFTER it
docker image prune -f
docker rmi registry.local/edge/vehicle-count:2.3.8 registry.local/edge/vehicle-count:2.3.9
python3 - <<'PY'
import json
p = "/etc/docker/daemon.json"; d = json.load(open(p))
d["log-driver"] = "json-file"; d["log-opts"] = {"max-size": "10m", "max-file": "3"}
json.dump(d, open(p, "w"), indent=4)
PY
systemctl restart docker
sleep 2
cd /opt/edge && docker compose restart event-uploader
sleep 2

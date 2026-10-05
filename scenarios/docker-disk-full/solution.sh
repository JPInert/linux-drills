set -e
# 1. free space: dangling layers and the two releases older than the rollback
sudo docker image prune -f
sudo docker rmi registry.local/edge/vehicle-count:2.3.8 registry.local/edge/vehicle-count:2.3.9
# 2. cap every container's log by default (keep the nvidia runtime block)
sudo tee /etc/docker/daemon.json >/dev/null <<'JSON'
{
    "runtimes": {
        "nvidia": {
            "args": [],
            "path": "nvidia-container-runtime"
        }
    },
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
JSON
sudo systemctl restart docker
for _ in $(seq 1 40); do [ -S /run/docker.sock ] && break; sleep 0.25; done
# 3. log settings apply to NEW containers: recreate them (drops the huge old log)
cd /opt/edge
sudo docker compose up -d --force-recreate
sleep 2

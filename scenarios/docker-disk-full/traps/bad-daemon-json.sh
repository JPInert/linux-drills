# hand-edited daemon.json with a trailing comma: dockerd refuses to start
docker image prune -f
cat > /etc/docker/daemon.json <<'JSON'
{
    "runtimes": {"nvidia": {"args": [], "path": "nvidia-container-runtime"}},
    "log-opts": {"max-size": "10m", "max-file": "3"},
}
JSON
systemctl restart docker
sleep 3

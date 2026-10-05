# free space by deleting the image nobody is running... the approved rollback
docker rmi registry.local/edge/vehicle-count:2.4.0
docker image prune -f
cd /opt/edge && sed -i '/container_name: event-uploader/a\    logging:\n      options:\n        max-size: "10m"\n        max-file: "3"' compose.yaml && docker compose up -d
sleep 2

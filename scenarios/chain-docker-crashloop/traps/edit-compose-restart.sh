# right edit, wrong verb: compose restart keeps the old container config
sed -i 's#fall-pose-v8.1.engine#fall-pose-v8.1-fp16.engine#' /opt/vehicle-count/compose.yaml
cd /opt/vehicle-count && docker compose restart vehicle-count
sleep 3

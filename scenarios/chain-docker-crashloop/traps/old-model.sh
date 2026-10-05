# new image, old model: runs, but the night-time false-alarm fix is gone
sed -i 's#models/v8.1:/models#models/v7:/models#; s#fall-pose-v8.1.engine#fall-pose-v7.engine#' /opt/vehicle-count/compose.yaml
cd /opt/vehicle-count && docker compose up -d
sleep 3

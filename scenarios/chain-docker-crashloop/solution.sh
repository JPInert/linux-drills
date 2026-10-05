set -e
F=/opt/vehicle-count/compose.yaml
# the model file the 8.1 package really ships (see models/v8.1/manifest.json)
sudo sed -i 's#FD_MODEL=/models/fall-pose-v8.1.engine#FD_MODEL=/models/fall-pose-v8.1-fp16.engine#' "$F"
cd /opt/vehicle-count
sudo docker compose config -q
sudo docker compose up -d
sleep 2

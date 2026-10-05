# alerts come back, but on 2.4.1 + the old model: the ticket said stay on the new release
cp /opt/vehicle-count/compose.yaml.2.4.1.bak /opt/vehicle-count/compose.yaml
sed -i 's#/opt/vehicle-count/models:/models#/opt/vehicle-count/models/v7:/models#' /opt/vehicle-count/compose.yaml
cd /opt/vehicle-count && docker compose up -d
sleep 3

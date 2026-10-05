# on the GPU again, but by rolling back to 2.3.8: the ticket says stay on 2.4.1
cp /opt/vehicle-count/compose.yaml.2.3.8.bak /opt/vehicle-count/compose.yaml
docker compose -f /opt/vehicle-count/compose.yaml up -d
sleep 2

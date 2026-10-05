set -e
F=/opt/vehicle-count/compose.yaml
# put the GPU reservation back under the vehicle-count service (keep the 2.4.1 image)
cat > /tmp/gpu-stanza.yaml <<'YML'
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
YML
sudo sed -i '/^    container_name: vehicle-count$/r /tmp/gpu-stanza.yaml' "$F"
sudo docker compose -f "$F" config -q
# recreate: restart would keep the old container config
sudo docker compose -f "$F" up -d
sleep 2

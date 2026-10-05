set -e
D=/etc/systemd/system/amazon-ssm-agent.service.d
sudo mkdir -p "$D"
sudo tee "$D/override.conf" >/dev/null <<'CONF'
[Service]
Environment="https_proxy=http://10.44.0.10:3128"
Environment="http_proxy=http://10.44.0.10:3128"
Environment="no_proxy=169.254.169.254,localhost,127.0.0.1"
CONF
sudo systemctl daemon-reload
sudo systemctl restart amazon-ssm-agent
sleep 2

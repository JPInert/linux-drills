set -e
f=/etc/hub-sync/hub.env
sudo sed -i "s|^HUB_TOKEN=.*|HUB_TOKEN=$(sudo cat /etc/hub-sync/token.new)|" $f
sudo systemctl restart hub-sync
sleep 5

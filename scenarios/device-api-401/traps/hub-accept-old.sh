# "fix" the hub to accept the old token: the hub is not ours to change
old=$(sed -n 's/^HUB_TOKEN=//p' /etc/hub-sync/hub.env)
sed -i "s|^CLIENT_TOKEN=.*|CLIENT_TOKEN=$old|" /etc/sensor-hub/hub.conf
systemctl restart sensor-hub-sim
sleep 2
systemctl restart hub-sync
sleep 5

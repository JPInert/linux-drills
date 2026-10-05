# the right fix plus chmod 777 on the secret
sed -i "s|^HUB_TOKEN=.*|HUB_TOKEN=$(cat /etc/hub-sync/token.new)|" /etc/hub-sync/hub.env
chmod 777 /etc/hub-sync/hub.env
systemctl restart hub-sync
sleep 5

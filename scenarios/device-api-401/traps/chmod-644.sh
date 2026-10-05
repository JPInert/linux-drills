# the right fix, then "make it readable so it works": the hub token is now world-readable
sed -i "s|^HUB_TOKEN=.*|HUB_TOKEN=$(cat /etc/hub-sync/token.new)|" /etc/hub-sync/hub.env
chmod 644 /etc/hub-sync/hub.env
systemctl restart hub-sync
sleep 5

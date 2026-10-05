# right token in the file, but the running process read hub.env at start: still 401
sed -i "s|^HUB_TOKEN=.*|HUB_TOKEN=$(cat /etc/hub-sync/token.new)|" /etc/hub-sync/hub.env
sleep 5

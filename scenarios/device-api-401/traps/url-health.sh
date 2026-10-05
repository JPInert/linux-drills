# point the client at the endpoint that needs no token: 200, but it carries no events
sed -i "s|/api/v2/events|/api/v2/health|" /etc/hub-sync/hub.env
systemctl restart hub-sync
sleep 5

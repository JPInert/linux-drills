# "maybe the API path changed": /api/v1 is gone in the new firmware (404), token still revoked
sed -i "s|/api/v2/|/api/v1/|" /etc/hub-sync/hub.env
systemctl restart hub-sync
sleep 5

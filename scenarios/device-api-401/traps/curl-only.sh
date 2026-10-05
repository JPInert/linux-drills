# prove the new token works with curl, then stop: the client still sends the old one
curl -sk -o /dev/null -H "Authorization: Bearer $(cat /etc/hub-sync/token.new)" \
  https://10.60.0.20:8443/api/v2/events
sleep 2

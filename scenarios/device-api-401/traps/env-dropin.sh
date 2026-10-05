# right token via a drop-in Environment=: EnvironmentFile wins over it (still 401), and
# anyone could read it with `systemctl show`
mkdir -p /etc/systemd/system/hub-sync.service.d
printf '[Service]\nEnvironment=HUB_TOKEN=%s\n' "$(cat /etc/hub-sync/token.new)" \
  > /etc/systemd/system/hub-sync.service.d/token.conf
systemctl daemon-reload
systemctl restart hub-sync
sleep 5

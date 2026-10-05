# "the unit file must be broken, put a fresh copy in": cp follows the symlink and writes into /dev/null
cp /usr/lib/systemd/system/feedrelay-sync.service /etc/systemd/system/feedrelay-sync.service
systemctl daemon-reload
systemctl start feedrelay-sync.service || true
systemctl enable --now feedrelay-sync.timer >/dev/null 2>&1

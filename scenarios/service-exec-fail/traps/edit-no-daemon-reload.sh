# both real fixes, but systemd is never told the unit file changed: it restarts the OLD definition
sed -i 's|^WorkingDirectory=.*|WorkingDirectory=/opt/feedrelay|' /etc/systemd/system/feedrelay.service
chmod 755 /opt/feedrelay/bin/run.sh
systemctl restart feedrelay || true

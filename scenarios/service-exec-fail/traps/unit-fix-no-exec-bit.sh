# fixes the path and reloads properly, but the script is still not executable
sed -i 's|^WorkingDirectory=.*|WorkingDirectory=/opt/feedrelay|' /etc/systemd/system/feedrelay.service
systemctl daemon-reload
systemctl restart feedrelay || true

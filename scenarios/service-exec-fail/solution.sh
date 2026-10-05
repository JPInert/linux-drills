set -e
sudo chmod 755 /opt/feedrelay/bin/run.sh
sudo sed -i 's|^WorkingDirectory=.*|WorkingDirectory=/opt/feedrelay|' /etc/systemd/system/feedrelay.service
sudo systemctl daemon-reload
sudo systemctl restart feedrelay
sleep 1
systemctl is-active --quiet feedrelay
curl -fs -m 3 http://localhost:8091/ | grep -q 'feedrelay ok'

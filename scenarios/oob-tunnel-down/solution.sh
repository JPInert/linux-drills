set -e
systemctl status oob-tunnel --no-pager | head -5 || true
sudo journalctl -u oob-tunnel --no-pager | tail -12
sudo ls -l /var/lib/oob/.ssh/
sudo chmod 600 /var/lib/oob/.ssh/id_ed25519
sudo ls -l /var/lib/oob/.ssh/id_ed25519
sudo systemctl restart oob-tunnel
sleep 3
sudo journalctl -u oob-tunnel --no-pager | tail -3
systemctl is-active oob-tunnel
sudo ss -tnp | grep 2222
nc -w 2 198.51.100.10 22003 < /dev/null | head -1

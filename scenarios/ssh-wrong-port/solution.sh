set -e
grep -ri '^Port' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ || true
sudo sed -i 's/^Port 2222/Port 22/' /etc/ssh/sshd_config.d/50-site.conf
sudo sshd -t
sudo systemctl restart ssh
sleep 1
nc -z localhost 22

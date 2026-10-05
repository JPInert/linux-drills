set -e
sudo sshd -t || true
sudo sed -i 's/^PermitRootLogon /PermitRootLogin /' /etc/ssh/sshd_config
sudo sshd -t
sudo systemctl reset-failed ssh
sudo systemctl start ssh
sleep 1
sudo sshd -T | grep -Eqi '^permitrootlogin no$'
sudo sshd -T | grep -Eqi '^passwordauthentication no$'
nc -z localhost 22

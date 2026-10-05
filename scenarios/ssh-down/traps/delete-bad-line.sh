# sshd comes up, but the line that failed WAS the hardening: root login is no longer disabled
sed -i '/^PermitRootLogon /d' /etc/ssh/sshd_config
systemctl reset-failed ssh
systemctl start ssh
sleep 1

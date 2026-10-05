# config is now valid, but nobody starts the service: still down
sed -i 's/^PermitRootLogon /PermitRootLogin /' /etc/ssh/sshd_config
sshd -t

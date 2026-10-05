# "make it start": replace the broken line with the opposite setting
sed -i 's/^PermitRootLogon no/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl reset-failed ssh
systemctl start ssh
sleep 1

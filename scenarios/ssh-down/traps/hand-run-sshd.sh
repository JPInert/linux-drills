# valid config, sshd started by hand outside systemd: the unit stays failed and it will not survive a reboot
sed -i 's/^PermitRootLogon /PermitRootLogin /' /etc/ssh/sshd_config
/usr/sbin/sshd
sleep 1

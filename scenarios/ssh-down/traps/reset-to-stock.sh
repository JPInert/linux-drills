# "just put the default config back": sshd comes up with none of the audit hardening
cp /usr/share/openssh/sshd_config /etc/ssh/sshd_config
systemctl reset-failed ssh
systemctl start ssh
sleep 1

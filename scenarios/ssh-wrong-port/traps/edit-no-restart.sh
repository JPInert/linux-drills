# right edit, but sshd is never told: it keeps listening on 2222 until restarted
sed -i 's/^Port 2222/Port 22/' /etc/ssh/sshd_config.d/50-site.conf
sshd -t

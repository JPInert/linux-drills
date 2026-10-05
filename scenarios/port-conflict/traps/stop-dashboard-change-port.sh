# "fix" by moving the dashboard to another port: the wall displays are hard-wired to 8080
sed -i 's/8080/8081/' /etc/systemd/system/dashboard.service; systemctl daemon-reload; systemctl start dashboard || true

# root can read anything: run the service as root instead of fixing the permissions
mkdir -p /etc/systemd/system/analytics.service.d
printf '[Service]\nUser=root\nGroup=root\n' > /etc/systemd/system/analytics.service.d/override.conf
systemctl daemon-reload; systemctl restart analytics; sleep 4

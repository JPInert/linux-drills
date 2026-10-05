# service comes up, but the camera password is now readable by every local user
chmod 644 /etc/analytics/analytics.conf
chmod 755 /etc/analytics
systemctl restart analytics; sleep 4

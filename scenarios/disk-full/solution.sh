set -e
sudo truncate -s 0 /var/log/analytics/detect.log
sudo sed -i 's/^LOG_LEVEL=.*/LOG_LEVEL=INFO/' /etc/analytics/analytics.conf
sudo systemctl restart analytics
sudo tee /etc/logrotate.d/analytics >/dev/null <<'ROT'
/var/log/analytics/detect.log {
    daily
    maxsize 20M
    rotate 4
    compress
    missingok
    notifempty
    copytruncate
}
ROT
